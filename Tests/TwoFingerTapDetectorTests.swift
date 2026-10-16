import XCTest
import Foundation
import CoreGraphics

@testable import TapperLib

class TwoFingerTapDetectorTests: XCTestCase {

    private typealias Contact = TwoFingerTapDetector.Contact

    var detector: TwoFingerTapDetector!
    var limits: TwoFingerTapDetector.Limits!
    var now: TimeInterval = 0
    var cursor = CGPoint(x: 400, y: 300)
    var cursorCalls = 0

    override func setUp() {
        super.setUp()
        detector = TwoFingerTapDetector()
        limits = TwoFingerTapDetector.Limits()
        now = 100
        cursor = CGPoint(x: 400, y: 300)
        cursorCalls = 0
    }

    private func finger(_ id: Int32, x: Float = 0.5, y: Float = 0.7, state: Int32 = 4, size: Float = 0.8) -> Contact {
        Contact(id: id, state: state, x: x, y: y, size: size)
    }

    @discardableResult
    private func frame(_ contacts: [Contact], after interval: TimeInterval = 0.01) -> TwoFingerTapDetector.Outcome? {
        now += interval
        return detector.update(contacts, now: now, limits: limits) {
            cursorCalls += 1
            return cursor
        }
    }

    /// Both fingers down for `frames` frames 10 ms apart, then an empty frame.
    private func tap(frames: Int = 8, a: Contact? = nil, b: Contact? = nil) -> TwoFingerTapDetector.Outcome? {
        for _ in 0..<frames { frame([a ?? finger(1, x: 0.4), b ?? finger(2, x: 0.6)]) }
        return frame([])
    }

    private func reason(_ outcome: TwoFingerTapDetector.Outcome?) -> String? {
        if case .rejected(let reason, _)? = outcome { return reason }
        return nil
    }

    // MARK: - Taps

    func testTwoFingersTappingTogetherIsATap() {
        let outcome = tap()
        XCTAssertTrue(outcome?.isTap == true, "Two fingers landing and lifting together should tap")
        if case .tap(let location, _)? = outcome {
            XCTAssertEqual(location, cursor)
        }
    }

    func testStaggeredFingersWithinTheGapStillTap() {
        frame([finger(1, x: 0.4)])
        frame([finger(1, x: 0.4)], after: 0.05)
        for _ in 0..<5 { frame([finger(1, x: 0.4), finger(2, x: 0.6)]) }
        frame([finger(2, x: 0.6)], after: 0.05)
        XCTAssertTrue(frame([])?.isTap == true)
    }

    func testDetectorStartsFreshAfterAnOutcome() {
        XCTAssertTrue(tap()?.isTap == true)
        XCTAssertTrue(tap()?.isTap == true, "A second two-finger tap must be judged on its own")
    }

    func testLightHoverContactsOfMeaningfulSizeTap() {
        let outcome = tap(a: finger(1, x: 0.4, state: 2, size: 0.3), b: finger(2, x: 0.6, state: 3, size: 0.3))
        XCTAssertTrue(outcome?.isTap == true)
    }

    // MARK: - Other gestures stay silent

    func testOneFingerTapYieldsNothing() {
        for _ in 0..<8 { frame([finger(1)]) }
        XCTAssertNil(frame([]))
    }

    func testEmptyFramesYieldNothingAndDoNotReadTheCursor() {
        XCTAssertNil(frame([]))
        XCTAssertNil(frame([]))
        XCTAssertEqual(cursorCalls, 0)
    }

    func testThreeFingersYieldNothing() {
        for _ in 0..<8 { frame([finger(1, x: 0.3), finger(2, x: 0.5), finger(3, x: 0.7)]) }
        XCTAssertNil(frame([]))
    }

    func testSequentialOneFingerTapsInOneSessionYieldNothing() {
        // Finger 1 hands over to finger 2 without both ever being down.
        for _ in 0..<5 { frame([finger(1)]) }
        for _ in 0..<5 { frame([finger(2)]) }
        XCTAssertNil(frame([]))
    }

    // MARK: - Rejections

    func testHeldTooLongIsRejected() {
        XCTAssertEqual(reason(tap(frames: 40))?.hasPrefix("held"), true)
    }

    func testTooShortIsRejected() {
        frame([finger(1, x: 0.4), finger(2, x: 0.6)], after: 0.005)
        frame([finger(1, x: 0.4), finger(2, x: 0.6)], after: 0.005)
        XCTAssertEqual(reason(frame([], after: 0.005))?.hasPrefix("duration"), true)
    }

    func testFingersLandingFarApartAreRejected() {
        frame([finger(1, x: 0.4)])
        frame([finger(1, x: 0.4)], after: 0.2)
        for _ in 0..<5 { frame([finger(1, x: 0.4), finger(2, x: 0.6)]) }
        XCTAssertEqual(reason(frame([]))?.hasPrefix("fingers landed"), true)
    }

    func testFingersLiftingFarApartAreRejected() {
        for _ in 0..<5 { frame([finger(1, x: 0.4), finger(2, x: 0.6)]) }
        frame([finger(2, x: 0.6)])
        frame([finger(2, x: 0.6)], after: 0.2)
        XCTAssertEqual(reason(frame([]))?.hasPrefix("fingers lifted"), true)
    }

    func testMovingFingerIsRejected() {
        frame([finger(1, x: 0.4), finger(2, x: 0.6)])
        frame([finger(1, x: 0.4), finger(2, x: 0.65)])
        XCTAssertEqual(reason(frame([]))?.hasPrefix("finger moved"), true)
    }

    func testFingerRubbingBackAndForthIsRejected() {
        for step in 0..<8 {
            let x: Float = step % 2 == 0 ? 0.6 : 0.63
            frame([finger(1, x: 0.4), finger(2, x: x)])
        }
        XCTAssertEqual(reason(frame([]))?.hasPrefix("finger path"), true)
    }

    func testMovingPointerIsRejected() {
        frame([finger(1, x: 0.4), finger(2, x: 0.6)])
        cursor.x += 20
        frame([finger(1, x: 0.4), finger(2, x: 0.6)])
        XCTAssertEqual(reason(frame([]))?.hasPrefix("pointer moved"), true)
    }

    func testReplacedFingerIsRejected() {
        for _ in 0..<3 { frame([finger(1, x: 0.4), finger(2, x: 0.6)]) }
        for _ in 0..<3 { frame([finger(3, x: 0.4), finger(2, x: 0.6)]) }
        XCTAssertEqual(reason(frame([])), "a third finger")
    }

    func testFaintHoverContactIsRejected() {
        let outcome = tap(b: finger(2, x: 0.6, state: 2, size: 0.1))
        XCTAssertEqual(reason(outcome)?.hasPrefix("contact too faint"), true)
    }

    func testHoverOnlyContactIsRejectedWhenHoverTapsAreOff() {
        limits.hoverTaps = false
        let outcome = tap(b: finger(2, x: 0.6, state: 2, size: 0.5))
        XCTAssertEqual(reason(outcome)?.hasPrefix("contact too faint"), true)
    }

    func testCancelledSessionIsRejectedWithItsReason() {
        frame([finger(1, x: 0.4), finger(2, x: 0.6)])
        detector.cancel(reason: "swipe")
        frame([finger(1, x: 0.4), finger(2, x: 0.6)])
        XCTAssertEqual(reason(frame([])), "swipe")
    }

    func testCancelWhileTheSurfaceIsEmptyIsIgnored() {
        detector.cancel(reason: "swipe")
        XCTAssertTrue(tap()?.isTap == true)
    }

    func testFingerIDsFollowTheSession() {
        frame([finger(7, x: 0.4), finger(9, x: 0.6)])
        XCTAssertEqual(detector.fingerIDs, [7, 9])
        frame([])
        XCTAssertEqual(detector.fingerIDs, [])
    }
}
