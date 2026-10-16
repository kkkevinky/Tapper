import Foundation
import CoreGraphics

/// Recognizes a two-finger tap, which Tapper turns into a right click as on a
/// trackpad: two fingers land together, stay still and lift together, quickly.
/// Pure value type, fed one frame at a time, so it can be driven with
/// recorded frames outside the app.
///
/// A session runs from the first contact on an empty surface until the
/// surface is empty again. Only a session that had exactly two fingers down at
/// once yields an outcome, on that empty frame; anything else stays silent so
/// one-finger taps and other gestures are left to their own code.
struct TwoFingerTapDetector {
    struct Contact {
        let id: Int32
        let state: Int32
        let x: Float
        let y: Float
        let size: Float
    }

    struct Limits {
        /// First landing to last lift, exclusive bounds, as for one-finger taps.
        var maxDuration: TimeInterval = 0.35
        var minDuration: TimeInterval = 0.03
        /// The two fingers must land within this time of each other, and lift
        /// within it too, so two overlapping one-finger taps are not a pair.
        var maxFingerGap: TimeInterval = 0.15
        /// Per finger, normalized: largest x or y offset from where it landed,
        /// and total path.
        var maxSurfaceMovement: Float = 0.04
        var maxSurfacePath: Float = 0.10
        /// Pointer movement (pixels) allowed between the first landing and the lift.
        var maxCursorMovement: CGFloat = 8
        /// A finger that never reached the touching state (4) counts only as a
        /// light tap: hover taps on, large enough and long enough.
        var hoverTaps = true
        var hoverMinSize: Float = 0.2
        var hoverMinDuration: TimeInterval = 0.05
    }

    enum Outcome: Equatable {
        case tap(location: CGPoint?, summary: String)
        case rejected(reason: String, summary: String)

        var isTap: Bool {
            if case .tap = self { return true }
            return false
        }
    }

    private struct Finger {
        let landed: TimeInterval
        var lastSeen: TimeInterval
        let originX: Float
        let originY: Float
        var lastX: Float
        var lastY: Float
        var maxMove: Float = 0
        var path: Float = 0
        var touched = false
        var maxSize: Float = 0
    }

    private var start: TimeInterval?
    private var fingers: [Int32: Finger] = [:]
    private var peak = 0
    private var startCursor: CGPoint?
    private var lastCursor: CGPoint?
    private var cursorMove: CGFloat = 0
    /// The first reason this session can no longer be a tap. Sticky until the
    /// surface is empty.
    private var failure: String?

    /// Ids of the fingers seen in the current session.
    var fingerIDs: Set<Int32> { Set(fingers.keys) }

    /// Rules the current session out, e.g. because the fingers turned out to
    /// be swiping or zooming. Ignored while the surface is empty.
    mutating func cancel(reason: @autoclosure () -> String) {
        guard start != nil, failure == nil else { return }
        failure = reason()
    }

    /// Feeds one frame. `cursor` is only called while the session can still
    /// become a tap.
    mutating func update(_ contacts: [Contact], now: TimeInterval, limits: Limits,
                         cursor: () -> CGPoint?) -> Outcome? {
        guard !contacts.isEmpty else {
            guard start != nil else { return nil }
            defer { self = TwoFingerTapDetector() }
            return finish(now: now, limits: limits, cursor: cursor)
        }

        if start == nil {
            start = now
            startCursor = cursor()
            lastCursor = startCursor
        }
        peak = max(peak, contacts.count)
        if contacts.count > 2 { cancel(reason: "\(contacts.count) fingers") }

        for contact in contacts {
            var finger = fingers[contact.id] ?? Finger(landed: now, lastSeen: now,
                                                       originX: contact.x, originY: contact.y,
                                                       lastX: contact.x, lastY: contact.y)
            finger.path += hypotf(contact.x - finger.lastX, contact.y - finger.lastY)
            finger.lastX = contact.x
            finger.lastY = contact.y
            finger.maxMove = max(finger.maxMove, abs(contact.x - finger.originX), abs(contact.y - finger.originY))
            finger.touched = finger.touched || contact.state == 4
            finger.maxSize = max(finger.maxSize, contact.size)
            finger.lastSeen = now
            fingers[contact.id] = finger

            if finger.maxMove > limits.maxSurfaceMovement {
                cancel(reason: String(format: "finger moved %.3f > %.3f", finger.maxMove, limits.maxSurfaceMovement))
            } else if finger.path > limits.maxSurfacePath {
                cancel(reason: String(format: "finger path %.3f > %.3f", finger.path, limits.maxSurfacePath))
            }
        }
        if fingers.count > 2 { cancel(reason: "a third finger") }
        if let start, now - start >= limits.maxDuration {
            cancel(reason: String(format: "held %.3fs", now - start))
        }
        // The pointer is sampled on every frame once both fingers are down.
        if peak == 2 { sampleCursor(cursor, limits: limits) }
        return nil
    }

    private mutating func sampleCursor(_ cursor: () -> CGPoint?, limits: Limits) {
        guard failure == nil, let location = cursor() else { return }
        lastCursor = location
        guard let startCursor else { self.startCursor = location; return }
        let moved = max(cursorMove, hypot(location.x - startCursor.x, location.y - startCursor.y))
        cursorMove = moved
        if moved > limits.maxCursorMovement {
            cancel(reason: String(format: "pointer moved %.1fpx > %.1fpx", moved, limits.maxCursorMovement))
        }
    }

    private mutating func finish(now: TimeInterval, limits: Limits, cursor: () -> CGPoint?) -> Outcome? {
        guard peak == 2, let start else { return nil }
        sampleCursor(cursor, limits: limits)

        let pair = fingers.values.sorted { $0.landed < $1.landed }
        let duration = now - start
        let landingGap = pair.count == 2 ? pair[1].landed - pair[0].landed : 0
        let liftGap = pair.count == 2 ? abs(pair[1].lastSeen - pair[0].lastSeen) : 0
        let summary = String(format: "dur=%.3fs landGap=%.3fs liftGap=%.3fs move=%.3f path=%.3f size=%.2f/%.2f cursor=%.1fpx",
                             duration, landingGap, liftGap,
                             pair.map(\.maxMove).max() ?? 0, pair.map(\.path).max() ?? 0,
                             pair.first?.maxSize ?? 0, pair.last?.maxSize ?? 0, cursorMove)

        if let failure { return .rejected(reason: failure, summary: summary) }
        guard pair.count == 2 else { return .rejected(reason: "a third finger", summary: summary) }
        for finger in pair where !finger.touched {
            let lifetime = finger.lastSeen - finger.landed
            guard limits.hoverTaps, finger.maxSize >= limits.hoverMinSize, lifetime >= limits.hoverMinDuration else {
                return .rejected(reason: String(format: "contact too faint (size %.2f, %.3fs)", finger.maxSize, lifetime),
                                 summary: summary)
            }
        }
        guard landingGap <= limits.maxFingerGap else {
            return .rejected(reason: String(format: "fingers landed %.3fs apart", landingGap), summary: summary)
        }
        guard liftGap <= limits.maxFingerGap else {
            return .rejected(reason: String(format: "fingers lifted %.3fs apart", liftGap), summary: summary)
        }
        guard duration > limits.minDuration, duration < limits.maxDuration else {
            return .rejected(reason: String(format: "duration %.3fs", duration), summary: summary)
        }
        return .tap(location: lastCursor, summary: summary)
    }
}
