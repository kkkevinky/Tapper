import CoreGraphics
import Foundation

enum ZoomCompatibility: Equatable {
    case standard, chrome

    init(bundleIdentifier: String?) {
        guard let id = bundleIdentifier else { self = .standard; return }
        self = id == "com.google.Chrome" || id.hasPrefix("com.google.Chrome.") ||
            id == "com.google.chrome.for.testing" ? .chrome : .standard
    }
}

/// Undocumented gesture fields are deliberately isolated here. This creates
/// magnify events, not Control-scroll accessibility screen zoom.
final class ZoomEventSynthesizer {
    static let syntheticMarker: Int64 = 0x4D545A4F4F4D
    private let post: (CGEvent) -> Void
    private var active = false
    private var outputActive = false
    private var needsChromePrimer = false
    private var anchor: CGPoint?
    private var outputAnchor: CGPoint?
    private let cursorLocation: () -> CGPoint?
    private let now: () -> TimeInterval
    // One startup boundary, not a rate gate on the continuing gesture. Native
    // delivery can merge adjacent magnify updates before Chrome applies its
    // threshold; merging the primer with movement makes the primer visible.
    static let chromePreparationInterval: TimeInterval = 0.024
    private var releaseAfter: TimeInterval?
    private struct Pending {
        let update: ZoomUpdate
        let compatibility: ZoomCompatibility
        let anchor: CGPoint
    }
    private var pending: [Pending] = []

    var hasPendingOutput: Bool { !pending.isEmpty }

    init(post: @escaping (CGEvent) -> Void = { $0.post(tap: .cgSessionEventTap) },
         cursorLocation: @escaping () -> CGPoint? = { CGEvent(source: nil)?.location },
         now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.post = post
        self.cursorLocation = cursorLocation
        self.now = now
    }

    // Serialized by ZoomCoordinator. The injected poster must not reenter it.
    func send(_ update: ZoomUpdate, compatibility: ZoomCompatibility = .standard) {
        guard update.magnification.isFinite, update.magnification > -1 else { return }
        switch update.phase {
        case .began:
            guard !active else { return }
        case .changed, .ended, .cancelled:
            guard active else { return }
        }
        if update.phase == .began {
            guard let location = cursorLocation(), location.x.isFinite, location.y.isFinite else { return }
            anchor = location
        }
        if update.phase == .cancelled { cancel(); return }
        guard let anchor else { return }
        // Bound memory if a caller produces events faster than time advances.
        guard pending.count < 256 else { cancel(); return }
        pending.append(Pending(update: update, compatibility: compatibility, anchor: anchor))
        active = update.phase == .began || update.phase == .changed
        if !active { self.anchor = nil }
        tick()
    }

    /// The owner calls this on its existing timer, after validating the target.
    /// No asynchronous closure can outlive cancellation or manager teardown.
    func tick() {
        if let deadline = releaseAfter, now() < deadline { return }
        releaseAfter = nil
        while let next = pending.first {
            outputAnchor = next.anchor
            if next.update.phase == .changed && next.update.magnification != 0 && needsChromePrimer {
                let scale = next.update.magnification > 0 ? 1.5 : Double(Float(0.667).nextUp)
                guard let event = makeEvent(ZoomUpdate(phase: .changed, magnification: scale - 1)) else {
                    cancel(); return
                }
                ZoomDiagnostics.log("Chrome preparation magnification=\(scale - 1)")
                post(event)
                needsChromePrimer = false
                releaseAfter = now() + Self.chromePreparationInterval
                return // Keep every real update, including a pending end.
            }
            guard let event = makeEvent(next.update) else { cancel(); return }
            pending.removeFirst()
            outputActive = next.update.phase == .began || next.update.phase == .changed
            if next.update.phase == .began { needsChromePrimer = next.compatibility == .chrome }
            if !outputActive { needsChromePrimer = false }
            post(event)
        }
        if !outputActive { outputAnchor = nil }
    }

    func cancel() {
        pending.removeAll()
        releaseAfter = nil
        if outputActive, let event = makeEvent(ZoomUpdate(phase: .cancelled, magnification: 0)) { post(event) }
        active = false
        outputActive = false
        needsChromePrimer = false
        anchor = nil
        outputAnchor = nil
    }

    private func makeEvent(_ update: ZoomUpdate) -> CGEvent? {
        guard let outputAnchor, let event = CGEvent(source: nil), let type = CGEventType(rawValue: 29),
              let kind = CGEventField(rawValue: 110),
              let amount = CGEventField(rawValue: 113),
              let phase = CGEventField(rawValue: 132) else { return nil }
        event.type = type
        event.location = outputAnchor
        event.flags = []
        event.setIntegerValueField(kind, value: 8)
        event.setDoubleValueField(amount, value: update.magnification)
        event.setIntegerValueField(phase, value: update.phase.rawValue)
        event.setIntegerValueField(.eventSourceUserData, value: Self.syntheticMarker)
        return event
    }
}
