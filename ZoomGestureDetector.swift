import Foundation

struct ZoomTouch: Equatable {
    let id: Int32
    let x: Double
    let y: Double
}

enum ZoomPhase: Int64 {
    // IOHIDEventPhaseBits, not NSEvent.Phase (whose bit assignments differ).
    case began = 1, changed = 2, ended = 4, cancelled = 8
}

struct ZoomUpdate: Equatable {
    let phase: ZoomPhase
    let magnification: Double
}

/// Pure recognizer. Its caller serializes access and owns the scroll deadline.
struct ZoomGestureDetector {
    enum State: Equatable { case idle, candidate, active, rejected }
    private(set) var state: State = .idle
    private(set) var device: Int32?
    private var origins: [Int32: ZoomTouch] = [:]
    private var lastCenter = 0.0
    private var filteredCenter = 0.0
    private var lastTimestamp = -Double.infinity
    private(set) var hasContacts = false

    var ownsTouches: Bool { state != .idle }

    mutating func reject() -> [ZoomUpdate] {
        let updates = state == .active ? [ZoomUpdate(phase: .cancelled, magnification: 0)] : []
        state = hasContacts ? .rejected : .idle
        return updates
    }

    mutating func reset() -> [ZoomUpdate] {
        let updates = state == .active ? [ZoomUpdate(phase: .cancelled, magnification: 0)] : []
        self = ZoomGestureDetector()
        return updates
    }

    mutating func process(device incoming: Int32, touches: [ZoomTouch], timestamp: Double,
                          dragging: Bool, sensitivity: Double, reversed: Bool,
                          contactCount: Int? = nil) -> [ZoomUpdate] {
        guard timestamp.isFinite, device == nil || device == incoming else { return [] }
        guard timestamp >= lastTimestamp else { return [] }
        lastTimestamp = timestamp
        let physicalCount = max(touches.count, contactCount ?? touches.count)
        if device == nil, physicalCount > 0 { device = incoming }
        hasContacts = physicalCount > 0
        if physicalCount == 0 {
            let updates = state == .active ? [ZoomUpdate(phase: .ended, magnification: 0)] : []
            self = ZoomGestureDetector()
            return updates
        }
        guard state != .rejected else { return [] }
        if touches.isEmpty {
            if state == .active {
                state = .rejected
                return [ZoomUpdate(phase: .ended, magnification: 0)]
            }
            if state == .candidate { state = .rejected }
            return []
        }
        guard Set(touches.map(\.id)).count == touches.count,
              touches.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return reject() }
        if touches.count != 2 {
            if state == .active {
                state = .rejected
                return [ZoomUpdate(phase: .ended, magnification: 0)]
            }
            if state == .candidate || touches.count > 2 { state = .rejected }
            return []
        }
        if dragging { return reject() }
        if state == .idle {
            origins = Dictionary(uniqueKeysWithValues: touches.map { ($0.id, $0) })
            lastCenter = touches.map(\.y).reduce(0, +) / 2
            filteredCenter = lastCenter
            state = .candidate
            return []
        }
        guard touches.allSatisfy({ origins[$0.id] != nil }) else { return reject() }
        let center = touches.map(\.y).reduce(0, +) / 2
        let gain = 2 * min(2, max(0.5, sensitivity.isFinite ? sensitivity : 1)) * (reversed ? -1.0 : 1.0)
        if state == .candidate {
            let deltas = touches.map { ($0.x - origins[$0.id]!.x, $0.y - origins[$0.id]!.y) }
            // Reject clear horizontal/opposed motion; a resting second finger
            // is decided by the scroll coordinator's bounded wait instead.
            if deltas.contains(where: { abs($0.0) >= 0.02 && abs($0.0) >= abs($0.1) }) ||
                (abs(deltas[0].1) >= 0.02 && abs(deltas[1].1) >= 0.02 && deltas[0].1 * deltas[1].1 < 0) {
                return reject()
            }
            guard deltas.allSatisfy({ abs($0.1) >= 0.02 && abs($0.1) >= 1.5 * abs($0.0) }),
                  deltas[0].1 * deltas[1].1 > 0 else { return [] }
            state = .active
            let displacement = center - lastCenter
            let excess = displacement - (displacement > 0 ? 0.02 : -0.02)
            lastCenter = center
            filteredCenter = center
            var updates = [ZoomUpdate(phase: .began, magnification: 0)]
            if abs(excess) > 0.000001 { updates.append(change(excess * gain)) }
            return updates
        }
        // Filter position, not velocity: stationary frames converge without
        // inventing motion. No remaining filter tail is emitted after lift.
        filteredCenter += 0.65 * (center - filteredCenter)
        let delta = filteredCenter - lastCenter
        lastCenter = filteredCenter
        return abs(delta) > 0.000001 ? [change(delta * gain)] : []
    }

    private func change(_ delta: Double) -> ZoomUpdate {
        ZoomUpdate(phase: .changed, magnification: exp(min(0.2, max(-0.2, delta))) - 1)
    }
}
