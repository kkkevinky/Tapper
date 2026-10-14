import Foundation
import CoreGraphics

struct ZoomTarget: Equatable {
    let process: Int32
    let window: Int
    let frontWindow: Int
    let compatibility: ZoomCompatibility

    init(process: Int32, window: Int, frontWindow: Int? = nil,
         compatibility: ZoomCompatibility = .standard) {
        self.process = process
        self.window = window
        self.frontWindow = frontWindow ?? window
        self.compatibility = compatibility
    }
}

/// Owns recognition, scroll arbitration and emission under one short lock.
/// No main-thread dispatch or callbacks into MultitouchManager while locked.
final class ZoomCoordinator: @unchecked Sendable {
    private let lock = NSLock()
    private var detector = ZoomGestureDetector()
    private var configuration = TapConfiguration.default
    private var available = false
    private var generation: UInt = 0
    private var buffered: [CGEvent] = []
    private var deadline: TimeInterval?
    private var tailDeadline: TimeInterval?
    private var tailHardDeadline: TimeInterval?
    private var suppressRemainder = false
    private var target: ZoomTarget?
    private let synthesizer: ZoomEventSynthesizer
    private let replay: (CGEvent) -> Void
    private let now: () -> TimeInterval
    private var blockedDevices = Set<Int32>()
    private var contacts: [Int32: Int] = [:]
    private var lastFrameTimestamp: [Int32: Double] = [:]

    init(now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         post: @escaping (CGEvent) -> Void = { $0.post(tap: .cgSessionEventTap) }) {
        self.now = now
        self.replay = post
        self.synthesizer = ZoomEventSynthesizer(post: post, now: now)
    }

    var currentGeneration: UInt { locked { generation } }
    var isEnabled: Bool { locked { configuration.zoomEnabled && available } }
    var needsTargetCheck: Bool { locked { detector.state == .candidate || detector.state == .active || synthesizer.hasPendingOutput || !buffered.isEmpty } }

    func configure(_ config: TapConfiguration, available: Bool) {
        locked {
            guard configuration != config || self.available != available else { return }
            cancelLocked()
            configuration = config
            self.available = available
        }
    }

    /// A configuration/target change consumes the remainder of existing contacts.
    /// A device teardown additionally forgets contacts that cannot send a lift.
    func cancel(forgetContacts: Bool = false) {
        locked {
            cancelLocked()
            if forgetContacts {
                blockedDevices.removeAll(); contacts.removeAll(); lastFrameTimestamp.removeAll()
            }
        }
    }

    @discardableResult
    func process(device: Int32, touches: [ZoomTouch], timestamp: Double, dragging: Bool,
                 generation expected: UInt, target currentTarget: ZoomTarget?, contactCount: Int? = nil) -> Bool {
        locked {
            guard generation == expected else { return true }
            guard timestamp.isFinite, timestamp > (lastFrameTimestamp[device] ?? -.infinity) else { return true }
            lastFrameTimestamp[device] = timestamp
            let physicalCount = max(touches.count, contactCount ?? touches.count)
            contacts[device] = physicalCount
            if blockedDevices.contains(device) {
                if physicalCount == 0 { blockedDevices.remove(device); contacts.removeValue(forKey: device) }
                return true
            }
            guard configuration.zoomEnabled && available else { return false }
            if let owner = detector.device, owner != device { return true }
            if (detector.state == .candidate || detector.state == .active || synthesizer.hasPendingOutput),
               target != nil && currentTarget != target { cancelLocked(); return true }
            // First contact of the next physical gesture terminates any old tail.
            if detector.device == nil && !touches.isEmpty { tailDeadline = nil; tailHardDeadline = nil }
            expireCandidateLocked()
            let ownedBefore = detector.ownsTouches
            let updates = detector.process(device: device, touches: touches, timestamp: timestamp,
                                           dragging: dragging, sensitivity: configuration.zoomSensitivity,
                                           reversed: configuration.zoomReversed, contactCount: physicalCount)
            if target == nil && (detector.state == .candidate || detector.state == .active) {
                target = currentTarget
                // No identifiable app window: leave native scrolling usable.
                if currentTarget == nil { emit(detector.reject()); replayLocked(); return true }
            }
            emit(updates)
            switch detector.state {
            case .active:
                buffered.removeAll(); deadline = nil
            case .idle, .rejected:
                replayLocked()
            case .candidate: break
            }
            if updates.contains(where: { $0.phase == .ended || $0.phase == .cancelled }) {
                suppressRemainder = physicalCount > 0
                beginTailLocked()
            }
            if physicalCount == 0 {
                if suppressRemainder { suppressRemainder = false; beginTailLocked() }
                contacts.removeValue(forKey: device)
                if !synthesizer.hasPendingOutput { target = nil }
            }
            return ownedBefore || detector.ownsTouches
        }
    }

    /// Return true to pass the original event, false to consume it. Never waits
    /// for a touch frame. Buffer copies are capped as a second deadline safeguard.
    func filter(_ event: CGEvent) -> Bool {
        locked {
            if event.getIntegerValueField(.eventSourceUserData) == ZoomEventSynthesizer.syntheticMarker { return true }
            guard configuration.zoomEnabled && available else { return true }
            let eventWindow = event.getIntegerValueField(.mouseEventWindowUnderMousePointer)
            if let target, eventWindow != 0 && eventWindow != target.window {
                cancelLocked()
                return true
            }
            expireCandidateLocked()
            if detector.state == .active || suppressRemainder { return false }
            if let end = tailDeadline {
                let phase = event.getIntegerValueField(.scrollWheelEventScrollPhase)
                let momentum = event.getIntegerValueField(.scrollWheelEventMomentumPhase)
                // Scroll phase is a bit mask; momentum is an enum (end=3).
                if now() >= end || (phase & 1 != 0 && momentum == 0) {
                    tailDeadline = nil
                } else {
                    if momentum == 3 { tailDeadline = nil }
                    else if momentum != 0 { tailDeadline = min(now() + 0.3, tailHardDeadline ?? end) }
                    return false
                }
            }
            // Momentum belongs to the previous physical scroll. A new contact
            // (including a state-2/3 contact before touching) must not be locked
            // out by that old sequence's changed/ended packets. During a new
            // two-finger candidate, stop the old inertia without starting the
            // 80 ms deadline for deciding the new physical scroll.
            if event.getIntegerValueField(.scrollWheelEventMomentumPhase) != 0 {
                return detector.state != .candidate
            }
            guard detector.state == .candidate else {
                // A scroll that already reached the app cannot turn into zoom
                // just because another finger is placed on the surface later.
                if detector.device != nil && detector.state == .idle { emit(detector.reject()) }
                return true
            }
            guard buffered.count < 128, let copy = event.copy() else {
                emit(detector.reject()); replayLocked(); return true
            }
            buffered.append(copy)
            if deadline == nil { deadline = now() + 0.08 }
            ZoomDiagnostics.log("scroll buffered count=\(buffered.count)")
            return false
        }
    }

    /// Called by a background timer, including when no new touch/event arrives.
    func tick(target currentTarget: ZoomTarget?) {
        locked {
            if (detector.state == .candidate || detector.state == .active || synthesizer.hasPendingOutput),
               target != nil && currentTarget != target { cancelLocked(); return }
            expireCandidateLocked()
            synthesizer.tick()
            if detector.state == .idle && !synthesizer.hasPendingOutput { target = nil }
            if let end = tailDeadline, now() >= end { tailDeadline = nil }
        }
    }

    private func expireCandidateLocked() {
        if let end = deadline, now() >= end {
            emit(detector.reject())
            replayLocked()
        }
    }

    private func replayLocked() {
        deadline = nil
        let events = buffered
        buffered.removeAll()
        for event in events {
            event.setIntegerValueField(.eventSourceUserData, value: ZoomEventSynthesizer.syntheticMarker)
            replay(event)
        }
    }

    private func cancelLocked() {
        generation &+= 1
        emit(detector.reset())
        synthesizer.cancel()
        blockedDevices.formUnion(contacts.filter { $0.value > 0 }.keys)
        buffered.removeAll(); deadline = nil; tailDeadline = nil; tailHardDeadline = nil
        suppressRemainder = false; target = nil
    }

    private func beginTailLocked() {
        tailDeadline = now() + 0.3
        tailHardDeadline = now() + 2
    }

    private func emit(_ updates: [ZoomUpdate]) {
        for update in updates {
            ZoomDiagnostics.log("output phase=\(update.phase) magnification=\(update.magnification)")
            synthesizer.send(update, compatibility: target?.compatibility ?? .standard)
        }
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        return body()
    }
}
