import AppKit
import CoreGraphics

/// The event tap runs in the main run loop's common modes. All deadline work
/// runs off the main thread so modal UI does not extend the 80 ms buffer window.
@MainActor
final class ZoomScrollFilter {
    let coordinator = ZoomCoordinator()
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var diagnosticTap: CFMachPort?
    private var diagnosticSource: CFRunLoopSource?
    private var timer: DispatchSourceTimer?
    private(set) var failure: String?
    var onFailure: (() -> Void)?

    func configure(_ configuration: TapConfiguration) {
        if !configuration.zoomEnabled {
            stop()
            failure = nil
            coordinator.configure(configuration, available: false)
            return
        }
        if tap == nil { start() }
        coordinator.configure(configuration, available: tap != nil)
    }

    func stop() {
        coordinator.cancel(forgetContacts: true)
        coordinator.configure(.default, available: false)
        timer?.cancel(); timer = nil
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        source = nil; tap = nil
        if let diagnosticTap { CFMachPortInvalidate(diagnosticTap) }
        if let diagnosticSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), diagnosticSource, .commonModes) }
        diagnosticTap = nil; diagnosticSource = nil
    }

    private func start() {
        let mask = CGEventMask(1) << CGEventType.scrollWheel.rawValue
        let context = Unmanaged.passUnretained(self).toOpaque()
        // Arbitrate after session processing, just before application delivery.
        // A session-head tap can miss scrolls injected later in that stream;
        // the later stage also reduces the touch-callback/scroll delivery race.
        // Replayed events are still posted at session level and bypass us by tag.
        guard let newTap = CGEvent.tapCreate(tap: .cgAnnotatedSessionEventTap, place: .tailAppendEventTap,
                                             options: .defaultTap, eventsOfInterest: mask,
                                             callback: { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            // This tap's source is attached only to the main run loop.
            return MainActor.assumeIsolated {
                let owner = Unmanaged<ZoomScrollFilter>.fromOpaque(context).takeUnretainedValue()
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    owner.failure = "Two-Finger Zoom paused: input filter unavailable. Toggle zoom off and on to retry."
                    owner.stop()
                    owner.onFailure?()
                    return Unmanaged.passUnretained(event)
                }
                let pass = owner.coordinator.filter(event)
                ZoomDiagnostics.log("scroll delivery=\(pass ? "pass" : "consume") phase=\(event.getIntegerValueField(.scrollWheelEventScrollPhase)) momentum=\(event.getIntegerValueField(.scrollWheelEventMomentumPhase)) dx=\(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)) dy=\(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1))")
                return pass ? Unmanaged.passUnretained(event) : nil
            }
        }, userInfo: context), let newSource = CFMachPortCreateRunLoopSource(nil, newTap, 0) else {
            failure = "Two-Finger Zoom unavailable: allow Accessibility access, then toggle zoom off and on."
            return
        }
        failure = nil
        tap = newTap; source = newSource
        CFRunLoopAddSource(CFRunLoopGetMain(), newSource, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)
        startDiagnosticObserver()
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "io.github.kkkevinky.tapper.zoom-deadline"))
        let coordinator = coordinator
        timer.schedule(deadline: .now(), repeating: .milliseconds(10), leeway: .milliseconds(1))
        timer.setEventHandler {
            // Window enumeration is never performed inside the event callback.
            let target = coordinator.needsTargetCheck ? Self.currentTarget() : nil
            coordinator.tick(target: target)
        }
        self.timer = timer
        timer.resume()
    }

    /// Opt-in, passive observation of gesture delivery for comparing trackpad
    /// input with our output. No keyboard events or window contents are read.
    private func startDiagnosticObserver() {
        guard ZoomDiagnostics.enabled else { return }
        let mask = (CGEventMask(1) << 29) | (CGEventMask(1) << 30) |
            (CGEventMask(1) << 31) | (CGEventMask(1) << CGEventType.scrollWheel.rawValue)
        guard let observer = CGEvent.tapCreate(tap: .cgAnnotatedSessionEventTap,
            place: .tailAppendEventTap, options: .listenOnly, eventsOfInterest: mask,
            callback: { _, type, event, _ in
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    ZoomDiagnostics.log("passive gesture observer disabled")
                    return Unmanaged.passUnretained(event)
                }
                let own = event.getIntegerValueField(.eventSourceUserData) == ZoomEventSynthesizer.syntheticMarker
                let kind = event.getIntegerValueField(CGEventField(rawValue: 110)!)
                let phase = event.getIntegerValueField(CGEventField(rawValue: 132)!)
                let amount = event.getDoubleValueField(CGEventField(rawValue: 113)!)
                ZoomDiagnostics.log("observed type=\(type.rawValue) own=\(own) kind=\(kind) phase=\(phase) magnification=\(amount) timestamp=\(event.timestamp) location=\(event.location)")
                return Unmanaged.passUnretained(event)
            }, userInfo: nil), let observerSource = CFMachPortCreateRunLoopSource(nil, observer, 0) else {
                ZoomDiagnostics.log("passive gesture observer unavailable")
                return
            }
        diagnosticTap = observer; diagnosticSource = observerSource
        CFRunLoopAddSource(CFRunLoopGetMain(), observerSource, .commonModes)
        CGEvent.tapEnable(tap: observer, enable: true)
        ZoomDiagnostics.log("passive gesture observer ready; own=false distinguishes native input")
    }

    /// Topmost regular window under the pointer identifies the gesture target.
    /// Metadata only: no window contents or screenshots are captured.
    nonisolated static func currentTarget() -> ZoomTarget? {
        guard let location = CGEvent(source: nil)?.location,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                       kCGNullWindowID) as? [[String: Any]] else { return nil }
        let frontWindow = windows.first { ($0[kCGWindowLayer as String] as? Int) == 0 }?[kCGWindowNumber as String] as? Int
        for window in windows {
            guard (window[kCGWindowLayer as String] as? Int) == 0,
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds), rect.contains(location),
                  let pid = window[kCGWindowOwnerPID as String] as? Int32,
                  let number = window[kCGWindowNumber as String] as? Int else { continue }
            let compatibility = ZoomCompatibility(bundleIdentifier: NSRunningApplication(processIdentifier: pid)?.bundleIdentifier)
            return ZoomTarget(process: pid, window: number, frontWindow: frontWindow,
                              compatibility: compatibility)
        }
        return nil
    }
}
