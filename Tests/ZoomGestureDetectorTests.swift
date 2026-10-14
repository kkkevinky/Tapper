import XCTest
@testable import TapperLib

final class ZoomGestureDetectorTests: XCTestCase {
    private var detector = ZoomGestureDetector()
    private var time = 1.0

    private func pair(_ y: Double = 0, x: Double = 0) -> [ZoomTouch] {
        [ZoomTouch(id: 1, x: 0.3 + x, y: 0.3 + y), ZoomTouch(id: 2, x: 0.7 + x, y: 0.3 + y)]
    }

    @discardableResult private func frame(_ touches: [ZoomTouch], device: Int32 = 1,
                                         dragging: Bool = false, reversed: Bool = false,
                                         sensitivity: Double = 1) -> [ZoomUpdate] {
        time += 0.01
        return detector.process(device: device, touches: touches, timestamp: time, dragging: dragging,
                                sensitivity: sensitivity, reversed: reversed)
    }

    func testBeginsOnlyAfterBothMoveVerticallyAndSubtractsThreshold() {
        frame(pair())
        XCTAssertEqual(detector.state, .candidate)
        XCTAssertTrue(frame(pair(0.01)).isEmpty)
        let events = frame(pair(0.03))
        XCTAssertEqual(events.map(\.phase), [.began, .changed])
        XCTAssertEqual(events.last!.magnification, exp(0.02) - 1, accuracy: 0.000001)
        XCTAssertGreaterThan(frame(pair(0.06)).last!.magnification, 0)
    }

    func testFingerOrderDoesNotMatter() {
        frame(pair())
        XCTAssertEqual(frame(pair(0.03).reversed()).first?.phase, .began)
    }

    func testStaggeredTouchDownUsesTwoFingerBaseline() {
        frame([pair()[0]])
        frame(pair(0.05))
        XCTAssertTrue(frame(pair(0.055)).isEmpty)
        XCTAssertEqual(frame(pair(0.08)).first?.phase, .began)
    }

    func testStationaryFingerDoesNotStartZoom() {
        frame(pair())
        XCTAssertTrue(frame([pair(0.10)[0], pair()[1]]).isEmpty)
        XCTAssertEqual(detector.state, .candidate)
    }

    func testHorizontalAndOpposedMotionRejectUntilAllLift() {
        for touches in [pair(0, x: 0.1), [pair(0.1)[0], pair(-0.1)[1]]] {
            _ = detector.reset()
            frame(pair())
            XCTAssertTrue(frame(touches).isEmpty)
            XCTAssertEqual(detector.state, .rejected)
            XCTAssertTrue(frame(pair(0.2)).isEmpty)
            frame([])
            XCTAssertEqual(detector.state, .idle)
        }
    }

    func testDiagonalRequiresVerticalDominance() {
        frame(pair())
        XCTAssertTrue(frame(pair(0.025, x: 0.02)).isEmpty)
        XCTAssertEqual(detector.state, .candidate)
        XCTAssertEqual(frame(pair(0.04, x: 0.02)).first?.phase, .began)
    }

    func testLiftEndsOnceAndRemainingFingerCannotRestart() {
        frame(pair()); frame(pair(0.03))
        XCTAssertEqual(frame([pair(0.03)[0]]).map(\.phase), [.ended])
        XCTAssertTrue(frame(pair(0.1)).isEmpty)
        XCTAssertTrue(frame([]).isEmpty)
        frame(pair())
        XCTAssertEqual(frame(pair(0.03)).first?.phase, .began)
    }

    func testThirdFingerEndsActiveAndRejectsNewGesture() {
        frame(pair()); frame(pair(0.03))
        XCTAssertEqual(frame(pair(0.03) + [ZoomTouch(id: 3, x: 0.5, y: 0.2)]).first?.phase, .ended)
        XCTAssertTrue(frame(pair(0.1)).isEmpty)
    }

    func testReplacementIdentifierCancels() {
        frame(pair()); frame(pair(0.03))
        XCTAssertEqual(frame([pair(0.04)[0], ZoomTouch(id: 9, x: 0.7, y: 0.34)]).first?.phase, .cancelled)
    }

    func testDragDoesNotBecomeZoom() {
        frame(pair(), dragging: true)
        XCTAssertEqual(detector.state, .rejected)
        XCTAssertTrue(frame(pair(0.1)).isEmpty)
    }

    func testDifferentDevicesDoNotCombineOrEndGesture() {
        frame(pair()); frame(pair(0.03))
        XCTAssertTrue(frame([], device: 2).isEmpty)
        XCTAssertEqual(detector.state, .active)
        XCTAssertEqual(frame([]).first?.phase, .ended)
    }

    func testReversalChangesSignAndSensitivityChangesLogScale() {
        frame(pair())
        let normal = frame(pair(0.04)).last!.magnification
        _ = detector.reset()
        frame(pair())
        let reversed = frame(pair(0.04), reversed: true).last!.magnification
        XCTAssertEqual((1 + normal) * (1 + reversed), 1, accuracy: 0.000001)
        _ = detector.reset()
        frame(pair())
        let faster = frame(pair(0.04), sensitivity: 2).last!.magnification
        XCTAssertGreaterThan(faster, normal)
    }

    func testNoUpdatesAfterLiftAndResetIsIdempotent() {
        frame(pair()); frame(pair(0.1))
        XCTAssertEqual(detector.reset().map(\.phase), [.cancelled])
        XCTAssertTrue(detector.reset().isEmpty)
        XCTAssertTrue(frame([]).isEmpty)
    }

    func testLingeringContactsMustAllDisappearBeforeNewGesture() {
        frame(pair()); frame(pair(0.03))
        time += 0.01
        let end = detector.process(device: 1, touches: [], timestamp: time, dragging: false,
                                   sensitivity: 1, reversed: false, contactCount: 2)
        XCTAssertEqual(end.map(\.phase), [.ended])
        XCTAssertEqual(detector.state, .rejected)
        XCTAssertTrue(frame(pair(0.1)).isEmpty)
        frame([]); frame(pair())
        XCTAssertEqual(frame(pair(0.03)).first?.phase, .began)
    }

    func testDuplicateIDsInvalidCoordinatesAndOldFramesAreSafe() {
        frame(pair())
        XCTAssertTrue(detector.process(device: 1, touches: pair(0.2), timestamp: 0,
                                       dragging: false, sensitivity: 1, reversed: false).isEmpty)
        XCTAssertEqual(detector.state, .candidate)
        frame([pair()[0], pair()[0]])
        XCTAssertEqual(detector.state, .rejected)
        _ = detector.reset()
        frame([ZoomTouch(id: 1, x: .nan, y: 0), pair()[1]])
        XCTAssertEqual(detector.state, .rejected)
    }
}
