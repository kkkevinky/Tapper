import XCTest
import Foundation
import CoreGraphics

@testable import TapperLib

class TapDetectorTests: XCTestCase {

    var detector: TapDetector!
    var currentTime: Date!

    override func setUp() {
        super.setUp()
        currentTime = Date(timeIntervalSince1970: 1_000)
        detector = TapDetector(
            tapTimeThreshold: 0.3,
            tapMovementThreshold: 5.0,
            rightClickTimeThreshold: 0.1,
            doubleTapTimeWindow: 0.3,
            dragThreshold: 3.0,
            nowProvider: { [unowned self] in self.currentTime }
        )
    }

    override func tearDown() {
        detector = nil
        currentTime = nil
        super.tearDown()
    }

    private func advanceTime(by interval: TimeInterval) {
        currentTime = currentTime.addingTimeInterval(interval)
    }

    // MARK: - Basic Tap Detection

    func testValidTap_WithinTimeAndMovementThreshold() {
        let startLocation = CGPoint(x: 100, y: 100)
        let endLocation = CGPoint(x: 102, y: 102) // 2.83 pixels away

        _ = detector.touchBegan(at: startLocation, isRightSide: false)
        advanceTime(by: 0.05)
        let result = detector.touchEnded(at: endLocation, isRightSide: false)

        XCTAssertTrue(result.shouldClick, "Valid tap should trigger a click")
        XCTAssertEqual(result.clickLocation?.x, endLocation.x)
        XCTAssertEqual(result.clickLocation?.y, endLocation.y)
        XCTAssertFalse(result.isRightClick, "Should be a left click")
        XCTAssertEqual(result.clickCount, 1)
    }

    func testValidTap_NoMovement() {
        let location = CGPoint(x: 100, y: 100)

        _ = detector.touchBegan(at: location, isRightSide: false)
        advanceTime(by: 0.05)
        let result = detector.touchEnded(at: location, isRightSide: false)

        XCTAssertTrue(result.shouldClick, "Tap with no movement should be valid")
        XCTAssertEqual(result.clickLocation, location)
    }

    func testInvalidTap_ExceedsMovementThreshold() {
        let startLocation = CGPoint(x: 100, y: 100)
        let endLocation = CGPoint(x: 110, y: 110) // 14.14 pixels away

        _ = detector.touchBegan(at: startLocation, isRightSide: false)
        advanceTime(by: 0.16)
        _ = detector.touchMoved(to: endLocation)
        advanceTime(by: 0.01)
        let result = detector.touchEnded(at: endLocation, isRightSide: false)

        XCTAssertFalse(result.shouldClick, "Tap exceeding movement threshold should be invalid")
    }

    func testInvalidTap_EndLocationExceedsMovementThresholdWithoutMoveEvent() {
        let startLocation = CGPoint(x: 100, y: 100)
        let endLocation = CGPoint(x: 112, y: 100)

        _ = detector.touchBegan(at: startLocation, isRightSide: false)
        advanceTime(by: 0.2)
        let result = detector.touchEnded(at: endLocation, isRightSide: false)

        XCTAssertFalse(
            result.shouldClick,
            "Final cursor displacement must be checked even when no move frame was received"
        )
    }

    func testQuickTap_AllowsSmallButBoundedMovement() {
        let startLocation = CGPoint(x: 100, y: 100)
        let toleratedLocation = CGPoint(x: 108, y: 100)

        _ = detector.touchBegan(at: startLocation, isRightSide: false)
        advanceTime(by: 0.05)
        let toleratedResult = detector.touchEnded(at: toleratedLocation, isRightSide: false)
        XCTAssertTrue(toleratedResult.shouldClick)

        advanceTime(by: 0.4)
        let excessiveLocation = CGPoint(x: 111, y: 100)
        _ = detector.touchBegan(at: startLocation, isRightSide: false)
        advanceTime(by: 0.05)
        let excessiveResult = detector.touchEnded(at: excessiveLocation, isRightSide: false)
        XCTAssertFalse(excessiveResult.shouldClick)
    }

    func testInvalidTap_ExceedsTimeThreshold() {
        let startLocation = CGPoint(x: 100, y: 100)

        _ = detector.touchBegan(at: startLocation, isRightSide: false)
        advanceTime(by: 0.35)
        let result = detector.touchEnded(at: startLocation, isRightSide: false)

        XCTAssertFalse(result.shouldClick, "Tap exceeding time threshold should be invalid")
    }

    // MARK: - Right Click Detection

    func testRightClick_HoldLongEnoughOnRightSide() {
        let location = CGPoint(x: 100, y: 100)

        _ = detector.touchBegan(at: location, isRightSide: true)
        advanceTime(by: 0.12) // Longer than right click threshold
        let result = detector.touchEnded(at: location, isRightSide: true)

        XCTAssertTrue(result.shouldClick, "Should trigger click")
        XCTAssertTrue(result.isRightClick, "Should be a right click")
        XCTAssertEqual(result.clickCount, 1)
    }

    func testLeftClick_ShortTapOnRightSide() {
        let location = CGPoint(x: 100, y: 100)

        _ = detector.touchBegan(at: location, isRightSide: true)
        advanceTime(by: 0.05) // End before right click threshold
        let result = detector.touchEnded(at: location, isRightSide: true)

        XCTAssertTrue(result.shouldClick, "Should trigger click")
        XCTAssertFalse(result.isRightClick, "Should be a left click (too quick for right click)")
    }

    func testLeftClick_OnLeftSide() {
        let location = CGPoint(x: 100, y: 100)

        _ = detector.touchBegan(at: location, isRightSide: false)
        advanceTime(by: 0.05)
        let result = detector.touchEnded(at: location, isRightSide: false)

        XCTAssertTrue(result.shouldClick, "Should trigger click")
        XCTAssertFalse(result.isRightClick, "Should be a left click")
    }

    // MARK: - Double-click and Drag Detection

    private func performFirstTap(at location: CGPoint = CGPoint(x: 100, y: 100)) {
        _ = detector.touchBegan(at: location, isRightSide: false)
        advanceTime(by: 0.05)
        let result = detector.touchEnded(at: location, isRightSide: false)
        XCTAssertTrue(result.shouldClick)
        XCTAssertEqual(result.clickCount, 1)
    }

    func testSecondTap_WaitsForDoubleClickOrDrag() {
        let location = CGPoint(x: 100, y: 100)
        performFirstTap(at: location)

        advanceTime(by: 0.1)
        let result = detector.touchBegan(at: location, isRightSide: false)

        XCTAssertFalse(result.shouldClick)
        XCTAssertFalse(result.isDragging, "Second touch must not start dragging immediately")
        XCTAssertTrue(detector.isSecondTapPending)
        XCTAssertEqual(detector.state, .secondTapPending)
    }

    func testSecondTap_QuickReleaseProducesDoubleClick() {
        let location = CGPoint(x: 100, y: 100)
        performFirstTap(at: location)
        advanceTime(by: 0.1)
        _ = detector.touchBegan(at: location, isRightSide: false)

        advanceTime(by: 0.05)
        let result = detector.touchEnded(at: location, isRightSide: false)

        XCTAssertTrue(result.shouldClick)
        XCTAssertFalse(result.isRightClick)
        XCTAssertEqual(result.clickCount, 2)
        XCTAssertFalse(result.isDragging)
    }

    func testSecondTap_SmallMovementStillProducesDoubleClick() {
        let start = CGPoint(x: 100, y: 100)
        let moved = CGPoint(x: 103, y: 100)
        performFirstTap(at: start)
        advanceTime(by: 0.1)
        _ = detector.touchBegan(at: start, isRightSide: false)

        let moveResult = detector.touchMoved(to: moved)
        XCTAssertFalse(moveResult.isDragging)
        advanceTime(by: 0.05)
        let endResult = detector.touchEnded(at: moved, isRightSide: false)
        XCTAssertTrue(endResult.shouldClick)
        XCTAssertEqual(endResult.clickCount, 2)
    }

    func testSecondTap_MovementPastTapThresholdStartsDrag() {
        let start = CGPoint(x: 100, y: 100)
        let moved = CGPoint(x: 106, y: 100)
        performFirstTap(at: start)
        advanceTime(by: 0.1)
        _ = detector.touchBegan(at: start, isRightSide: false)

        let result = detector.touchMoved(to: moved)

        XCTAssertTrue(result.isDragging)
        XCTAssertEqual(result.dragLocation, moved)
        XCTAssertTrue(detector.isDragging)
        XCTAssertFalse(result.shouldClick)
    }

    func testDoubleTapDrag_EndsWithoutSecondClick() {
        let start = CGPoint(x: 100, y: 100)
        let moved = CGPoint(x: 106, y: 100)
        performFirstTap(at: start)

        advanceTime(by: 0.1)
        _ = detector.touchBegan(at: start, isRightSide: false)
        _ = detector.touchMoved(to: moved)
        XCTAssertTrue(detector.isDragging)

        let endResult = detector.touchEnded(at: moved, isRightSide: false)
        XCTAssertFalse(endResult.shouldClick)
        XCTAssertEqual(endResult.clickCount, 0)
        XCTAssertFalse(endResult.isDragging, "Should not be dragging after release")
        XCTAssertFalse(detector.isDragging, "Detector should not be in dragging state")
    }

    func testSecondTap_AfterTimeoutIsAnotherSingleClick() {
        let location = CGPoint(x: 100, y: 100)
        performFirstTap(at: location)
        advanceTime(by: 0.4)

        _ = detector.touchBegan(at: location, isRightSide: false)
        XCTAssertEqual(detector.state, .touching)
        advanceTime(by: 0.05)
        let result = detector.touchEnded(at: location, isRightSide: false)
        XCTAssertTrue(result.shouldClick)
        XCTAssertEqual(result.clickCount, 1)
    }

    func testSecondTap_TooFarAwayIsAnotherSingleClick() {
        let first = CGPoint(x: 100, y: 100)
        let second = CGPoint(x: 106, y: 100)
        performFirstTap(at: first)
        advanceTime(by: 0.1)

        _ = detector.touchBegan(at: second, isRightSide: false)
        XCTAssertEqual(detector.state, .touching)
        advanceTime(by: 0.05)
        let result = detector.touchEnded(at: second, isRightSide: false)
        XCTAssertTrue(result.shouldClick)
        XCTAssertEqual(result.clickCount, 1)
    }

    func testSecondTap_HeldTooLongDoesNotClick() {
        let location = CGPoint(x: 100, y: 100)
        performFirstTap(at: location)
        advanceTime(by: 0.1)
        _ = detector.touchBegan(at: location, isRightSide: false)

        advanceTime(by: 0.31)
        let result = detector.touchEnded(at: location, isRightSide: false)
        XCTAssertFalse(result.shouldClick)
        XCTAssertEqual(result.clickCount, 0)
    }

    func testSecondTap_RightSideHoldPreservesRightClick() {
        let location = CGPoint(x: 100, y: 100)
        performFirstTap(at: location)
        advanceTime(by: 0.1)
        _ = detector.touchBegan(at: location, isRightSide: true)

        advanceTime(by: 0.12)
        let result = detector.touchEnded(at: location, isRightSide: true)
        XCTAssertTrue(result.shouldClick)
        XCTAssertTrue(result.isRightClick)
        XCTAssertEqual(result.clickCount, 1)
    }

    func testSecondTap_EndMovementPastThresholdDoesNotRetroactivelyDragOrClick() {
        let start = CGPoint(x: 100, y: 100)
        let end = CGPoint(x: 106, y: 100)
        performFirstTap(at: start)
        advanceTime(by: 0.1)
        _ = detector.touchBegan(at: start, isRightSide: false)

        advanceTime(by: 0.05)
        let result = detector.touchEnded(at: end, isRightSide: false)
        XCTAssertFalse(result.shouldClick)
        XCTAssertFalse(result.isDragging)
    }

    // MARK: - Drag Threshold (Anti-jitter)

    func testDragThreshold_SmallMovementAfterDragStartIgnored() {
        let start = CGPoint(x: 100, y: 100)
        let dragStart = CGPoint(x: 106, y: 100)
        let smallMove = CGPoint(x: 108, y: 100)

        performFirstTap(at: start)
        advanceTime(by: 0.1)
        _ = detector.touchBegan(at: start, isRightSide: false)
        _ = detector.touchMoved(to: dragStart)

        let moveResult = detector.touchMoved(to: smallMove)
        XCTAssertTrue(moveResult.isDragging, "Should still be dragging")
        XCTAssertNil(moveResult.dragLocation, "Should not generate drag location for small movement")
    }

    func testDragThreshold_LargeMovementAfterDragStartAccepted() {
        let start = CGPoint(x: 100, y: 100)
        let dragStart = CGPoint(x: 106, y: 100)
        let largeMove = CGPoint(x: 110, y: 100)

        performFirstTap(at: start)
        advanceTime(by: 0.1)
        _ = detector.touchBegan(at: start, isRightSide: false)
        _ = detector.touchMoved(to: dragStart)

        let moveResult = detector.touchMoved(to: largeMove)
        XCTAssertTrue(moveResult.isDragging, "Should still be dragging")
        XCTAssertNotNil(moveResult.dragLocation, "Should generate drag location for large movement")
    }

    // MARK: - State Management

    func testReset_ClearsAllState() {
        let location = CGPoint(x: 100, y: 100)

        _ = detector.touchBegan(at: location, isRightSide: false)
        XCTAssertTrue(detector.isTracking)

        detector.reset()
        XCTAssertFalse(detector.isTracking)
        XCTAssertFalse(detector.isDragging)

        let result = detector.touchEnded(at: location, isRightSide: false)
        XCTAssertFalse(result.shouldClick, "Should not detect tap after reset")
    }

    func testReset_ClearsPendingDoubleTapHistory() {
        let location = CGPoint(x: 100, y: 100)
        performFirstTap(at: location)
        detector.reset()
        advanceTime(by: 0.1)

        _ = detector.touchBegan(at: location, isRightSide: false)
        XCTAssertEqual(detector.state, .touching)
        advanceTime(by: 0.05)
        let result = detector.touchEnded(at: location, isRightSide: false)
        XCTAssertEqual(result.clickCount, 1)
    }

    func testIsTracking_InitiallyFalse() {
        XCTAssertFalse(detector.isTracking, "Detector should not be tracking initially")
    }

    func testIsTracking_TrueAfterTouchBegan() {
        _ = detector.touchBegan(at: CGPoint(x: 100, y: 100), isRightSide: false)
        XCTAssertTrue(detector.isTracking, "Detector should be tracking after touch began")
    }

    func testState_TransitionsCorrectly() {
        XCTAssertEqual(detector.state, .idle, "Should start in idle state")

        _ = detector.touchBegan(at: CGPoint(x: 100, y: 100), isRightSide: false)
        XCTAssertEqual(detector.state, .touching, "Should be in touching state")

        _ = detector.touchEnded(at: CGPoint(x: 100, y: 100), isRightSide: false)
        XCTAssertEqual(detector.state, .idle, "Should return to idle state")
    }

    // MARK: - Cursor Path (Rub / Round-trip Movement)

    func testTap_OscillatingWithinDisplacementLimitIsRejectedByPathLength() {
        let startLocation = CGPoint(x: 100, y: 100)
        let nudged = CGPoint(x: 102, y: 100)

        _ = detector.touchBegan(at: startLocation, isRightSide: false)
        // Eight 2px back-and-forth moves: peak displacement stays at 2px
        // (within the 5px limit), but the total path is 16px, beyond the
        // 3x path budget. A rub like this is movement, not a tap.
        for index in 1...8 {
            advanceTime(by: 0.02)
            _ = detector.touchMoved(to: index.isMultiple(of: 2) ? startLocation : nudged)
        }
        advanceTime(by: 0.02)
        let result = detector.touchEnded(at: startLocation, isRightSide: false)

        XCTAssertFalse(result.shouldClick, "Round-trip cursor movement must not produce a click")
    }

    func testTap_SmallTremorWithinPathBudgetStillClicks() {
        let startLocation = CGPoint(x: 100, y: 100)
        let nudged = CGPoint(x: 102, y: 100)

        _ = detector.touchBegan(at: startLocation, isRightSide: false)
        // Three 2px moves: total path 6px, well within budget — hand tremor
        // must not suppress a genuine tap.
        for index in 1...3 {
            advanceTime(by: 0.02)
            _ = detector.touchMoved(to: index.isMultiple(of: 2) ? startLocation : nudged)
        }
        advanceTime(by: 0.02)
        let result = detector.touchEnded(at: startLocation, isRightSide: false)

        XCTAssertTrue(result.shouldClick, "Minor tremor should not invalidate a tap")
        XCTAssertEqual(result.clickCount, 1)
    }

    // MARK: - Edge Cases

    func testTouchEnded_WithoutTouchBegan() {
        let location = CGPoint(x: 100, y: 100)
        let result = detector.touchEnded(at: location, isRightSide: false)

        XCTAssertFalse(result.shouldClick, "Should not detect tap without touchBegan")
    }

    func testTouchMoved_WithoutTouchBegan() {
        let location = CGPoint(x: 100, y: 100)
        let result = detector.touchMoved(to: location)

        XCTAssertFalse(result.isDragging, "Should handle touchMoved without touchBegan")
    }

}
