import XCTest
import CoreGraphics
@testable import TapperLib

final class ZoomCoordinatorTests: XCTestCase {
    private var clock = 1.0
    private var output: [CGEvent] = []
    private var coordinator: ZoomCoordinator!
    private let target = ZoomTarget(process: 12, window: 23)

    override func setUp() {
        coordinator = ZoomCoordinator(now: { [unowned self] in self.clock }, post: { [unowned self] in self.output.append($0) })
        coordinator.configure(TapConfiguration(zoomEnabled: true), available: true)
    }

    private func pair(_ y: Double = 0) -> [ZoomTouch] {
        [ZoomTouch(id: 1, x: 0.3, y: y), ZoomTouch(id: 2, x: 0.7, y: y)]
    }

    @discardableResult private func frame(_ touches: [ZoomTouch], generation: UInt? = nil) -> Bool {
        clock += 0.001
        return coordinator.process(device: 1, touches: touches, timestamp: clock, dragging: false,
                                   generation: generation ?? coordinator.currentGeneration, target: target)
    }

    private func scroll(_ delta: Int32 = 1, phase: Int64 = 2, momentum: Int64 = 0) -> CGEvent {
        let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: delta, wheel2: 0, wheel3: 0)!
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
        event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentum)
        return event
    }

    private var scrollOutput: [CGEvent] { output.filter { $0.type == .scrollWheel } }
    private var phases: [Int64] { output.filter { $0.type.rawValue == 29 }.map { $0.getIntegerValueField(CGEventField(rawValue: 132)!) } }

    func testNormalAndDisabledScrollPassThrough() {
        XCTAssertTrue(coordinator.filter(scroll()))
        coordinator.configure(.default, available: true)
        XCTAssertFalse(frame(pair()))
        XCTAssertTrue(coordinator.filter(scroll()))
        XCTAssertTrue(output.isEmpty)
    }

    func testRecognizedZoomDiscardsBufferAndSuppressesScroll() {
        XCTAssertTrue(frame(pair()))
        XCTAssertFalse(coordinator.filter(scroll()))
        frame(pair(0.03))
        XCTAssertEqual(phases.first, ZoomPhase.began.rawValue)
        XCTAssertTrue(scrollOutput.isEmpty)
        XCTAssertFalse(coordinator.filter(scroll()))
    }

    func testZoomConsumesBothScrollAxesAndMomentumThroughLift() {
        frame(pair())
        let initial = scroll(4, phase: 1)
        initial.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: 6)
        XCTAssertFalse(coordinator.filter(initial))
        frame(pair(0.03))
        for phase: Int64 in [1, 2, 4, 8, 0] {
            let event = scroll(5, phase: phase)
            event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: -7)
            XCTAssertFalse(coordinator.filter(event))
        }
        frame(pair(0.06))
        frame([pair(0.06)[0]])
        clock += 1 // A remaining finger must not release scroll suppression.
        XCTAssertFalse(coordinator.filter(scroll(9)))
        frame([])
        for momentum: Int64 in [1, 2, 3] {
            XCTAssertFalse(coordinator.filter(scroll(12, phase: 0, momentum: momentum)))
        }
        XCTAssertTrue(scrollOutput.isEmpty)
        XCTAssertTrue(coordinator.filter(scroll(3, phase: 1)))
    }

    func testTimeoutReplaysInOrderAndLocksUntilLift() {
        frame(pair())
        XCTAssertFalse(coordinator.filter(scroll(3)))
        XCTAssertFalse(coordinator.filter(scroll(7)))
        clock += 0.081
        coordinator.tick(target: target)
        XCTAssertEqual(scrollOutput.map { $0.getIntegerValueField(.scrollWheelEventPointDeltaAxis1) }, [3, 7])
        XCTAssertTrue(coordinator.filter(scrollOutput[0]))
        frame(pair(0.1))
        XCTAssertTrue(phases.isEmpty)
        frame([]); frame(pair()); frame(pair(0.04))
        XCTAssertEqual(phases.first, ZoomPhase.began.rawValue)
    }

    func testHorizontalRejectionReplaysImmediately() {
        frame(pair())
        XCTAssertFalse(coordinator.filter(scroll(4)))
        frame([ZoomTouch(id: 1, x: 0.5, y: 0), ZoomTouch(id: 2, x: 0.9, y: 0)])
        XCTAssertEqual(scrollOutput.count, 1)
        XCTAssertTrue(coordinator.filter(scroll()))
    }

    func testWindowSwitchDiscardsBufferAndConsumesRemainingTouches() {
        frame(pair()); XCTAssertFalse(coordinator.filter(scroll()))
        coordinator.tick(target: ZoomTarget(process: 12, window: 24))
        XCTAssertTrue(output.isEmpty)
        XCTAssertTrue(frame(pair(0.1)))
        XCTAssertTrue(output.isEmpty)
        frame([]); frame(pair()); frame(pair(0.03))
        XCTAssertEqual(phases.first, ZoomPhase.began.rawValue)
    }

    func testLosingWindowTargetDiscardsRatherThanReplays() {
        frame(pair()); XCTAssertFalse(coordinator.filter(scroll()))
        coordinator.tick(target: nil)
        XCTAssertTrue(coordinator.filter(scroll()))
        XCTAssertTrue(output.isEmpty)
    }

    func testFrontWindowChangeCancelsEvenIfPointerRemainsOverOldWindow() {
        frame(pair()); XCTAssertFalse(coordinator.filter(scroll()))
        coordinator.tick(target: ZoomTarget(process: 12, window: 23, frontWindow: 24))
        XCTAssertTrue(output.isEmpty)
        frame(pair(0.04))
        XCTAssertTrue(phases.isEmpty)
    }

    func testMissingTargetDoesNotEnableZoomOrBlockOrdinaryScroll() {
        XCTAssertTrue(coordinator.process(device: 1, touches: pair(), timestamp: clock, dragging: false,
                                          generation: coordinator.currentGeneration, target: nil))
        frame(pair(0.04))
        XCTAssertTrue(output.isEmpty)
        XCTAssertTrue(coordinator.filter(scroll()))
    }

    func testUnavailableFilterCancelsExactlyOnceAndFailsOpen() {
        frame(pair()); frame(pair(0.03))
        coordinator.configure(TapConfiguration(zoomEnabled: true), available: false)
        coordinator.configure(TapConfiguration(zoomEnabled: true), available: false)
        XCTAssertEqual(phases.filter { $0 == ZoomPhase.cancelled.rawValue }.count, 1)
        XCTAssertTrue(coordinator.filter(scroll()))
    }

    func testGenerationPreventsOldFrameFromStartingNewZoom() {
        let old = coordinator.currentGeneration
        coordinator.cancel(forgetContacts: true)
        frame(pair(), generation: old); frame(pair(0.1), generation: old)
        XCTAssertTrue(output.isEmpty)
        frame(pair()); frame(pair(0.03))
        XCTAssertEqual(phases.first, ZoomPhase.began.rawValue)
    }

    func testOldLiftFrameCannotEndCurrentGesture() {
        frame(pair()); frame(pair(0.03))
        _ = coordinator.process(device: 1, touches: [], timestamp: 0.5, dragging: false,
                                generation: coordinator.currentGeneration, target: target)
        frame(pair(0.06))
        XCTAssertFalse(phases.contains(ZoomPhase.ended.rawValue))
        XCTAssertFalse(phases.contains(ZoomPhase.cancelled.rawValue))
        frame([])
        XCTAssertEqual(phases.last, ZoomPhase.ended.rawValue)
    }

    func testTargetCompatibilityReachesSynthesizerAndDoesNotLeakToPDF() {
        let chrome = ZoomTarget(process: 42, window: 50, compatibility: .chrome)
        for touches in [pair(), pair(0.03)] {
            clock += 0.01
            _ = coordinator.process(device: 1, touches: touches, timestamp: clock, dragging: false,
                                    generation: coordinator.currentGeneration, target: chrome)
        }
        for _ in 0..<20 { clock += 0.011; coordinator.tick(target: chrome) }
        clock += 0.01
        _ = coordinator.process(device: 1, touches: [], timestamp: clock, dragging: false,
                                generation: coordinator.currentGeneration, target: chrome)
        XCTAssertEqual(phases.first, 1)
        XCTAssertEqual(phases.last, 4)
        let magnifications = output.map { $0.getDoubleValueField(CGEventField(rawValue: 113)!) }
        XCTAssertEqual(magnifications[1], 0.5)
        output.removeAll()
        frame(pair()); frame(pair(0.03)); frame([])
        XCTAssertEqual(phases, [1, 2, 4])
        XCTAssertLessThan(output[1].getDoubleValueField(CGEventField(rawValue: 113)!), 0.03)
    }

    func testTargetChangeOrDisableCancelsChromeGesture() {
        let chrome = ZoomTarget(process: 42, window: 50, compatibility: .chrome)
        for disable in [false, true] {
            coordinator.cancel(forgetContacts: true)
            coordinator.configure(TapConfiguration(zoomEnabled: true), available: true)
            output.removeAll()
            for touches in [pair(), pair(0.03)] {
                clock += 0.01
                coordinator.process(device: 1, touches: touches, timestamp: clock, dragging: false,
                                    generation: coordinator.currentGeneration, target: chrome)
            }
            XCTAssertEqual(phases, [1, 2])
            if disable { coordinator.configure(.default, available: true) }
            else { coordinator.tick(target: target) }
            XCTAssertEqual(phases.last, ZoomPhase.cancelled.rawValue)
            let count = output.count
            for _ in 0..<100 { clock += 0.01; coordinator.tick(target: chrome) }
            XCTAssertEqual(output.count, count)
            XCTAssertTrue(coordinator.filter(scroll()))
        }
    }

    func testTargetChangeAfterQuickChromeLiftDiscardsDelayedOutput() {
        let chrome = ZoomTarget(process: 42, window: 50, compatibility: .chrome)
        for touches in [pair(), pair(0.03), []] {
            clock += 0.001
            coordinator.process(device: 1, touches: touches, timestamp: clock, dragging: false,
                                generation: coordinator.currentGeneration, target: chrome)
        }
        XCTAssertEqual(phases, [1, 2])
        XCTAssertTrue(coordinator.needsTargetCheck)
        clock += 0.1
        coordinator.tick(target: target)
        XCTAssertEqual(phases, [1, 2, 8])
        coordinator.tick(target: chrome)
        XCTAssertEqual(phases, [1, 2, 8])
        XCTAssertFalse(coordinator.needsTargetCheck)
    }

    func testRemainingFingerAndMomentumAreConsumedButNextGesturePasses() {
        frame(pair()); frame(pair(0.03)); frame([pair(0.03)[0]])
        clock += 0.5
        XCTAssertFalse(coordinator.filter(scroll()))
        frame([])
        XCTAssertFalse(coordinator.filter(scroll(momentum: 1)))
        XCTAssertFalse(coordinator.filter(scroll(momentum: 3)))
        XCTAssertTrue(coordinator.filter(scroll(phase: 1)))
        XCTAssertEqual(phases.filter { $0 == ZoomPhase.ended.rawValue }.count, 1)
    }

    func testMomentumSuppressionIsBoundedWithoutEndEvent() {
        frame(pair()); frame(pair(0.03)); frame([])
        clock += 0.31
        coordinator.tick(target: nil)
        XCTAssertTrue(coordinator.filter(scroll()))
    }

    func testContinuingMomentumRefreshesInactivityButHasHardLimit() {
        frame(pair()); frame(pair(0.03)); frame([])
        for _ in 0..<9 {
            clock += 0.2
            XCTAssertFalse(coordinator.filter(scroll(momentum: 2)))
        }
        clock += 0.21
        XCTAssertTrue(coordinator.filter(scroll(momentum: 2)))
    }

    func testDisconnectDropsBufferAndNewDeviceSequenceCanStart() {
        frame(pair()); XCTAssertFalse(coordinator.filter(scroll()))
        coordinator.cancel(forgetContacts: true)
        XCTAssertTrue(output.isEmpty)
        frame(pair()); frame(pair(0.03))
        XCTAssertEqual(phases.first, ZoomPhase.began.rawValue)
    }

    func testNewPhysicalContactClearsMomentumTail() {
        frame(pair()); frame(pair(0.03)); frame([])
        frame([pair()[0]])
        XCTAssertTrue(coordinator.filter(scroll()))
    }

    func testExistingSingleFingerScrollCannotSwitchToZoom() {
        frame([pair()[0]])
        XCTAssertTrue(coordinator.filter(scroll()))
        frame(pair()); frame(pair(0.03))
        XCTAssertTrue(phases.isEmpty)
    }

    func testPreviousScrollMomentumCannotRejectNewTouchSequence() {
        // Recorded 16:12:17.315: first contact is state 3 (not yet state 4).
        // One millisecond later, the previous scroll sends momentum-ended.
        for momentum: Int64 in [1, 2, 3] {
            coordinator.cancel(forgetContacts: true)
            output.removeAll()
            clock += 1
            coordinator.process(device: 1, touches: [], timestamp: clock, dragging: false,
                                generation: coordinator.currentGeneration, target: nil, contactCount: 1)
            XCTAssertTrue(coordinator.filter(scroll(0, phase: 0, momentum: momentum)))
            frame([pair()[0]])
            frame(pair())
            frame(pair(0.03))
            XCTAssertEqual(phases.first, ZoomPhase.began.rawValue)
        }
    }

    func testOldMomentumDoesNotStartNewCandidatesScrollDeadline() {
        frame(pair())
        XCTAssertFalse(coordinator.filter(scroll(5, phase: 0, momentum: 2)))
        clock += 0.1
        coordinator.tick(target: target)
        XCTAssertFalse(coordinator.filter(scroll(0, phase: 0, momentum: 3)))
        frame(pair(0.03))
        XCTAssertEqual(phases.first, ZoomPhase.began.rawValue)
        XCTAssertTrue(scrollOutput.isEmpty)
    }

    func testReconfigurationCancelsAndWaitsForFreshTouches() {
        frame(pair()); frame(pair(0.03))
        coordinator.configure(TapConfiguration(zoomEnabled: true, zoomReversed: true), available: true)
        frame(pair(0.1))
        XCTAssertEqual(phases.filter { $0 == ZoomPhase.began.rawValue }.count, 1)
        frame([]); frame(pair()); frame(pair(0.03))
        XCTAssertEqual(phases.filter { $0 == ZoomPhase.began.rawValue }.count, 2)
        XCTAssertLessThan(output.last!.getDoubleValueField(CGEventField(rawValue: 113)!), 0)
    }
}
