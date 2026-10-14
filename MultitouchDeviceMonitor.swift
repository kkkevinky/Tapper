import Foundation
import IOKit

/// Watches the IORegistry for Magic Mouse connect/disconnect events.
///
/// The periodic health check in `MultitouchRestartManager` only notices a
/// reconnect when its next poll fires (30–300 s once stable). These IOKit
/// matching notifications make reconnects register within moments. The health
/// check stays in place as a fallback for failures the registry does not
/// surface (e.g. the multitouch stack dying without the device disappearing).
///
/// The Magic Mouse multitouch driver publishes itself under the
/// `AppleMultitouchMouseHIDEventDriver` IORegistry class (trackpads use a
/// separate trackpad driver class). `AppleMagicMouse` has no instances on
/// macOS 27 with the USB-C Magic Mouse, so watching it never fired.
final class MultitouchDeviceMonitor: @unchecked Sendable {

    enum Event {
        case connected
        case disconnected
    }

    /// Fired on the monitor's private queue whenever a matching device is
    /// added to or removed from the registry. Set before `start()`.
    var onEvent: ((Event) -> Void)?

    private let serviceClass: String
    private let queue = DispatchQueue(label: "io.github.kkkevinky.tapper.device-monitor")
    private let lock = NSLock()
    private var isStopped = true
    private var notificationPort: IONotificationPortRef?
    private var matchedIterator: io_iterator_t = IO_OBJECT_NULL
    private var terminatedIterator: io_iterator_t = IO_OBJECT_NULL

    init(serviceClass: String = "AppleMultitouchMouseHIDEventDriver") {
        self.serviceClass = serviceClass
    }

    deinit {
        stop()
    }

    func start() {
        lock.lock()
        guard notificationPort == nil else {
            lock.unlock()
            return
        }

        guard let port = IONotificationPortCreate(kIOMainPortDefault) else {
            lock.unlock()
            return
        }

        isStopped = false
        IONotificationPortSetDispatchQueue(port, queue)

        // The context pointer must outlive the registrations; the owner keeps
        // this monitor alive for as long as it runs.
        let context = Unmanaged.passUnretained(self).toOpaque()

        var matched = io_iterator_t(IO_OBJECT_NULL)
        let matchedResult = IOServiceAddMatchingNotification(
            port,
            kIOMatchedNotification,
            IOServiceMatching(serviceClass),
            { context, iterator in
                MultitouchDeviceMonitor.handle(iterator: iterator, context: context, event: .connected)
            },
            context,
            &matched
        )

        var terminated = io_iterator_t(IO_OBJECT_NULL)
        let terminatedResult = IOServiceAddMatchingNotification(
            port,
            kIOTerminatedNotification,
            IOServiceMatching(serviceClass),
            { context, iterator in
                MultitouchDeviceMonitor.handle(iterator: iterator, context: context, event: .disconnected)
            },
            context,
            &terminated
        )

        guard matchedResult == KERN_SUCCESS, terminatedResult == KERN_SUCCESS else {
            // Partial registration is useless: drop the port and fall back to
            // health-check-only monitoring.
            if matched != IO_OBJECT_NULL { IOObjectRelease(matched) }
            if terminated != IO_OBJECT_NULL { IOObjectRelease(terminated) }
            IONotificationPortSetDispatchQueue(port, nil)
            IONotificationPortDestroy(port)
            isStopped = true
            lock.unlock()
            return
        }

        matchedIterator = matched
        terminatedIterator = terminated
        notificationPort = port
        lock.unlock()

        // The returned iterators are pre-populated with devices that already
        // match; drain them silently so only *future* arrivals fire callbacks.
        drain(matched)
        drain(terminated)

        #if DEBUG
        print("🔌 Device monitor started (watching \(serviceClass))")
        #endif
    }

    func stop() {
        lock.lock()
        guard let port = notificationPort else {
            lock.unlock()
            return
        }

        // Mark stopped first so callbacks already queued on `queue` bail out
        // instead of firing `onEvent` for a torn-down owner.
        isStopped = true
        notificationPort = nil
        let iterators = [matchedIterator, terminatedIterator]
        matchedIterator = IO_OBJECT_NULL
        terminatedIterator = IO_OBJECT_NULL
        lock.unlock()

        IONotificationPortSetDispatchQueue(port, nil)
        IONotificationPortDestroy(port)
        for iterator in iterators where iterator != IO_OBJECT_NULL {
            IOObjectRelease(iterator)
        }

        #if DEBUG
        print("🔌 Device monitor stopped")
        #endif
    }

    /// Entry point for the C notification callbacks. Runs on `queue`.
    private static func handle(iterator: io_iterator_t, context: UnsafeMutableRawPointer?, event: Event) {
        guard let context else { return }
        let monitor = Unmanaged<MultitouchDeviceMonitor>.fromOpaque(context).takeUnretainedValue()
        monitor.process(iterator: iterator, event: event)
    }

    private func process(iterator: io_iterator_t, event: Event) {
        drain(iterator)

        lock.lock()
        let stopped = isStopped
        lock.unlock()

        guard !stopped else { return }
        onEvent?(event)
    }

    /// Drains a notification iterator, releasing the entries. The kernel only
    /// re-arms a matching notification once its iterator has been drained.
    private func drain(_ iterator: io_iterator_t) {
        guard iterator != IO_OBJECT_NULL else { return }
        while true {
            let entry = IOIteratorNext(iterator)
            if entry == IO_OBJECT_NULL { break }
            IOObjectRelease(entry)
        }
    }
}
