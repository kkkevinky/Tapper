import Foundation
import CoreGraphics

/// Synthesizes and posts the mouse events for detected taps and drags.
///
/// Called directly from the multitouch touch queue: CGEvent posting is
/// thread-safe, and skipping the main-queue hop keeps tap latency independent
/// of main-thread work (menu tracking, modal alerts). The shared hidSystemState
/// source keeps click state consistent across synthesized events, including
/// drags.
final class EventSynthesizer: @unchecked Sendable {

    private let eventSource: CGEventSource?
    /// Injected so unit tests can observe events without posting real input.
    private let postEvent: (CGEvent) -> Void

    /// Serializes event posts and guards `isDragging`: taps arrive on the
    /// touch queue while cancel can arrive from the main thread. Never call
    /// back into MultitouchManager while holding this lock.
    private let lock = NSLock()
    private var isDragging = false

    init(eventSource: CGEventSource? = CGEventSource(stateID: .hidSystemState),
         postEvent: @escaping (CGEvent) -> Void = { $0.post(tap: .cghidEventTap) }) {
        self.eventSource = eventSource
        self.postEvent = postEvent
    }

    /// Posts a synthesized click (mouse down + up) at the given location.
    func synthesizeClick(at location: CGPoint, isRightClick: Bool, clickCount: Int) {
        let clickState = Int64(max(1, clickCount))
        let button: CGMouseButton = isRightClick ? .right : .left
        let downType: CGEventType = isRightClick ? .rightMouseDown : .leftMouseDown
        let upType: CGEventType = isRightClick ? .rightMouseUp : .leftMouseUp

        lock.lock()
        defer { lock.unlock() }

        postMouseEvent(downType, at: location, button: button, clickState: clickState)
        postMouseEvent(upType, at: location, button: button, clickState: clickState)
    }

    /// Posts the mouse-down that begins a drag. Ignored when a drag is active.
    func startDrag(at location: CGPoint) {
        lock.lock()
        defer { lock.unlock() }

        guard !isDragging else { return }
        isDragging = true
        postMouseEvent(.leftMouseDown, at: location, button: .left, clickState: 1)
    }

    /// Posts a drag movement. Ignored when no drag is active.
    func moveDrag(to location: CGPoint) {
        lock.lock()
        defer { lock.unlock() }

        guard isDragging else { return }
        postMouseEvent(.leftMouseDragged, at: location, button: .left, clickState: 1)
    }

    /// Posts the mouse-up that ends a drag. Ignored when no drag is active.
    func endDrag(at location: CGPoint) {
        lock.lock()
        defer { lock.unlock() }

        guard isDragging else { return }
        isDragging = false
        postMouseEvent(.leftMouseUp, at: location, button: .left, clickState: 1)
    }

    /// Ends an in-flight drag at the current cursor position.
    /// Used when the feature is toggled off, the system sleeps, or the app quits.
    func cancelActiveDrag() {
        lock.lock()
        defer { lock.unlock() }

        guard isDragging else { return }
        isDragging = false
        let location = CGEvent(source: nil)?.location ?? .zero
        postMouseEvent(.leftMouseUp, at: location, button: .left, clickState: 1)
    }

    private func postMouseEvent(_ type: CGEventType, at location: CGPoint, button: CGMouseButton, clickState: Int64) {
        guard let event = CGEvent(mouseEventSource: eventSource, mouseType: type, mouseCursorPosition: location, mouseButton: button) else {
            return
        }
        event.setIntegerValueField(.mouseEventClickState, value: clickState)
        postEvent(event)
    }
}
