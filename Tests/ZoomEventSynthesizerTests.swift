import AppKit
import XCTest
@testable import TapperLib

final class ZoomEventSynthesizerTests: XCTestCase {
    func testConstructedEventsDecodeAsAppKitMagnificationWithoutPosting() {
        var events: [CGEvent] = []
        let synthesizer = ZoomEventSynthesizer(post: { events.append($0) })
        synthesizer.send(ZoomUpdate(phase: .began, magnification: 0))
        synthesizer.send(ZoomUpdate(phase: .changed, magnification: 0.125))
        synthesizer.send(ZoomUpdate(phase: .ended, magnification: 0))
        XCTAssertEqual(events.count, 3)
        let native = events.compactMap(NSEvent.init(cgEvent:))
        XCTAssertEqual(native.count, 3)
        XCTAssertEqual(native.map(\.type), [.magnify, .magnify, .magnify])
        XCTAssertEqual(native[1].magnification, 0.125, accuracy: 0.000001)
        XCTAssertEqual(native.map(\.phase), [.began, .changed, .ended])
        XCTAssertTrue(events.allSatisfy { $0.getIntegerValueField(.eventSourceUserData) == ZoomEventSynthesizer.syntheticMarker })
    }

    func testNoDuplicateBeginOrEndAndNoChangeOutsideGesture() {
        var phases: [ZoomPhase] = []
        let synthesizer = ZoomEventSynthesizer(post: { phases.append(ZoomPhase(rawValue: $0.getIntegerValueField(CGEventField(rawValue: 132)!))!) })
        for phase in [ZoomPhase.changed, .ended, .began, .began, .changed, .cancelled, .cancelled, .changed] {
            synthesizer.send(ZoomUpdate(phase: phase, magnification: 0))
        }
        XCTAssertEqual(phases, [.began, .changed, .cancelled])
    }

    // Consumer-side regression oracle: Chrome 153 accumulates FLOAT scales,
    // compares them to DOUBLE thresholds and discards zoom-disabled updates.
    // See RenderWidgetHostViewMac::PinchEvent and
    // RenderWidgetHostViewInput::OnGestureEventForPinchAck in Chromium.
    private func scalesAppliedByChrome(_ events: [CGEvent]) -> [Float] {
        var accumulated: Float = 1
        var thresholdReached = false
        var visible: [Float] = []
        for native in events.compactMap(NSEvent.init(cgEvent:)) {
            if native.phase == .began {
                accumulated = 1
                thresholdReached = false
            } else if native.phase == .changed {
                let scale = Float(native.magnification + 1)
                if !thresholdReached {
                    accumulated *= scale
                    thresholdReached = Double(accumulated) < 0.667 || Double(accumulated) > 1.5
                }
                if thresholdReached { visible.append(scale) }
            }
        }
        return visible
    }

    func testShortConsecutiveChromeGesturesRetainMovementAndEndDuringStartup() {
        var events: [CGEvent] = []
        var clock = 0.0
        let synthesizer = ZoomEventSynthesizer(post: { events.append($0) }, now: { clock })
        var expected: [Float] = []
        for index in 0..<20 {
            let delta = index % 2 == 0 ? 0.01 : -0.01
            synthesizer.send(ZoomUpdate(phase: .began, magnification: 0), compatibility: .chrome)
            synthesizer.send(ZoomUpdate(phase: .changed, magnification: delta))
            synthesizer.send(ZoomUpdate(phase: .ended, magnification: 0))
            XCTAssertTrue(synthesizer.hasPendingOutput)
            clock += 0.025
            synthesizer.tick()
            XCTAssertFalse(synthesizer.hasPendingOutput)
            expected.append(Float(1 + delta))
        }
        XCTAssertEqual(events.count, 80)
        XCTAssertEqual(scalesAppliedByChrome(events), expected)
    }

    func testDenseContinuousUpdatesPreserveEveryIncrementIncludingReversal() {
        var events: [CGEvent] = []
        var clock = 0.0
        let synthesizer = ZoomEventSynthesizer(post: { events.append($0) }, now: { clock })
        synthesizer.send(ZoomUpdate(phase: .began, magnification: 0), compatibility: .chrome)
        let deltas = (0..<40).map { $0 < 20 ? 0.012 : -0.014 }
        for delta in deltas {
            clock += 0.001
            synthesizer.send(ZoomUpdate(phase: .changed, magnification: delta))
        }
        synthesizer.send(ZoomUpdate(phase: .ended, magnification: 0))
        XCTAssertFalse(synthesizer.hasPendingOutput)
        XCTAssertEqual(events.count, deltas.count + 3)
        XCTAssertEqual(scalesAppliedByChrome(events), deltas.map { Float(1 + $0) })
        let product = scalesAppliedByChrome(events).reduce(1.0) { $0 * Double($1) }
        let expected = deltas.reduce(1.0) { $0 * Double(Float(1 + $1)) }
        XCTAssertEqual(product, expected, accuracy: 0.000001)
    }

    func testPrimerHasDeliveryGapButContinuingUpdatesAreImmediate() {
        for delta in [0.01, -0.01] {
            var clock = 0.0
            var posted: [(Double, CGEvent)] = []
            let synthesizer = ZoomEventSynthesizer(post: { posted.append((clock, $0)) }, now: { clock })
            synthesizer.send(ZoomUpdate(phase: .began, magnification: 0), compatibility: .chrome)
            synthesizer.send(ZoomUpdate(phase: .changed, magnification: delta))
            XCTAssertEqual(posted.count, 2) // Begin and preparation only.
            clock = 0.023
            synthesizer.tick()
            XCTAssertEqual(posted.count, 2)
            clock = 0.025
            synthesizer.tick()
            XCTAssertEqual(posted.count, 3)
            XCTAssertGreaterThanOrEqual(posted[2].0 - posted[1].0, 0.024)
            for _ in 0..<10 {
                let count = posted.count
                synthesizer.send(ZoomUpdate(phase: .changed, magnification: delta))
                XCTAssertEqual(posted.count, count + 1) // No ongoing pacing gate.
            }
            synthesizer.send(ZoomUpdate(phase: .ended, magnification: 0))
            XCTAssertEqual(scalesAppliedByChrome(posted.map { $0.1 }), Array(repeating: Float(1 + delta), count: 11))
        }
    }

    func testQueuedNextGestureKeepsItsOwnAnchorAndPreparation() {
        var clock = 0.0
        var pointer = CGPoint(x: 10, y: 20)
        var events: [CGEvent] = []
        let synthesizer = ZoomEventSynthesizer(post: { events.append($0) }, cursorLocation: { pointer }, now: { clock })
        for x in [10.0, 50.0] {
            pointer.x = x
            synthesizer.send(ZoomUpdate(phase: .began, magnification: 0), compatibility: .chrome)
            synthesizer.send(ZoomUpdate(phase: .changed, magnification: 0.01))
            synthesizer.send(ZoomUpdate(phase: .ended, magnification: 0))
        }
        clock += 0.025
        synthesizer.tick()
        clock += 0.025
        synthesizer.tick()
        XCTAssertEqual(events.count, 8)
        XCTAssertEqual(events.map { $0.location.x }, [10, 10, 10, 10, 50, 50, 50, 50])
        XCTAssertEqual(scalesAppliedByChrome(events), [Float(1.01), Float(1.01)])
    }

    func testCancellationDropsPendingMovementEvenAfterInputHasEnded() {
        var clock = 0.0
        var events: [CGEvent] = []
        let synthesizer = ZoomEventSynthesizer(post: { events.append($0) }, now: { clock })
        synthesizer.send(ZoomUpdate(phase: .began, magnification: 0), compatibility: .chrome)
        synthesizer.send(ZoomUpdate(phase: .changed, magnification: 0.01))
        synthesizer.send(ZoomUpdate(phase: .ended, magnification: 0))
        synthesizer.cancel()
        clock = 10
        synthesizer.tick()
        XCTAssertEqual(events.map { $0.getIntegerValueField(CGEventField(rawValue: 132)!) }, [1, 2, 8])
        XCTAssertTrue(scalesAppliedByChrome(events).isEmpty)
        XCTAssertFalse(synthesizer.hasPendingOutput)
    }

    func testOldSmallSlideSequenceRemainsInsideChromesDeadZone() {
        var events: [CGEvent] = []
        let synthesizer = ZoomEventSynthesizer(post: { events.append($0) })
        synthesizer.send(ZoomUpdate(phase: .began, magnification: 0))
        for _ in 0..<5 { synthesizer.send(ZoomUpdate(phase: .changed, magnification: 0.01)) }
        synthesizer.send(ZoomUpdate(phase: .ended, magnification: 0))
        XCTAssertTrue(scalesAppliedByChrome(events).isEmpty)
        XCTAssertEqual(events.count, 7) // Standard/PDF output remains unchanged.
    }

    func testCancellationResetsChromePreparationAndNextAppPolicy() {
        var events: [CGEvent] = []
        let synthesizer = ZoomEventSynthesizer(post: { events.append($0) })
        synthesizer.send(ZoomUpdate(phase: .began, magnification: 0), compatibility: .chrome)
        synthesizer.send(ZoomUpdate(phase: .changed, magnification: 0.01))
        synthesizer.send(ZoomUpdate(phase: .cancelled, magnification: 0))
        let count = events.count
        synthesizer.send(ZoomUpdate(phase: .changed, magnification: 0.1))
        XCTAssertEqual(events.count, count)
        synthesizer.send(ZoomUpdate(phase: .began, magnification: 0))
        synthesizer.send(ZoomUpdate(phase: .changed, magnification: 0.01), compatibility: .chrome)
        synthesizer.send(ZoomUpdate(phase: .ended, magnification: 0))
        XCTAssertEqual(events.count, count + 3)
    }

    func testCompatibilityIsLimitedToChromeApplications() {
        for id in ["com.google.Chrome", "com.google.Chrome.canary", "com.google.Chrome.beta", "com.google.chrome.for.testing"] {
            XCTAssertEqual(ZoomCompatibility(bundleIdentifier: id), .chrome)
        }
        for id in [nil, "com.apple.Preview", "com.adobe.Acrobat.Pro", "com.apple.Safari", "com.google.Chromecast"] {
            XCTAssertEqual(ZoomCompatibility(bundleIdentifier: id), .standard)
        }
    }

    func testPointerMovementDoesNotMoveZoomAnchorIncludingChromePrimer() {
        for compatibility in [ZoomCompatibility.standard, .chrome] {
            var events: [CGEvent] = []
            var clock = 0.0
            var pointer = CGPoint(x: 420, y: 300)
            let start = pointer
            var reads = 0
            let synthesizer = ZoomEventSynthesizer(post: { events.append($0) }, cursorLocation: {
                reads += 1
                return pointer
            }, now: { clock })
            synthesizer.send(ZoomUpdate(phase: .began, magnification: 0), compatibility: compatibility)
            pointer = CGPoint(x: 450, y: 350)
            synthesizer.send(ZoomUpdate(phase: .changed, magnification: 0.01))
            pointer = CGPoint(x: 480, y: 400)
            synthesizer.send(ZoomUpdate(phase: .changed, magnification: -0.01))
            synthesizer.send(ZoomUpdate(phase: .ended, magnification: 0))
            clock = 1
            synthesizer.tick()
            XCTAssertGreaterThanOrEqual(events.count, 4)
            XCTAssertTrue(events.allSatisfy { $0.location == start })
            XCTAssertEqual(reads, 1)
            let decoded = events.compactMap(NSEvent.init(cgEvent:))
            XCTAssertEqual(decoded.count, events.count)
            XCTAssertEqual(Set(decoded.map { NSStringFromPoint($0.locationInWindow) }).count, 1)
        }
    }

    func testFreshGestureCapturesNewAnchorAfterEndOrCancellation() {
        for terminal in [ZoomPhase.ended, .cancelled] {
            var events: [CGEvent] = []
            var pointer = CGPoint(x: -300, y: 180) // Secondary display coordinates.
            let synthesizer = ZoomEventSynthesizer(post: { events.append($0) }, cursorLocation: { pointer })
            synthesizer.send(ZoomUpdate(phase: .began, magnification: 0))
            pointer = CGPoint(x: 700, y: 540)
            synthesizer.send(ZoomUpdate(phase: terminal, magnification: 0))
            XCTAssertEqual(events[1].location, events[0].location)
            synthesizer.send(ZoomUpdate(phase: .began, magnification: 0))
            synthesizer.send(ZoomUpdate(phase: .changed, magnification: 0.01))
            XCTAssertTrue(events.suffix(2).allSatisfy { $0.location == pointer })
        }
    }
}
