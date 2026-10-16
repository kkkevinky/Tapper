// Portions of this file are adapted from third-party code (translated to Swift
// where it was C or C++) and modified. The full license texts are in
// THIRD_PARTY_NOTICES.md.
//  - InstantSpaceSwitcher, Copyright (c) 2026 jurplel, MIT License:
//    DockSwipePoster and SpaceSwipeEngine.progressSign / naturalScrolling.
//    SpaceLayout.current and the Space-index prediction and edge check are
//    based on it.
//  - FasterSwiper, Copyright 2026 Matthew Bowen, Apache License 2.0: the IOHID
//    payload serialization in DockSwipePoster (via InstantSpaceSwitcher).
//  - palmpad, Copyright (c) 2026 Xin, MIT License: the re-sent end events.

import Foundation
import CoreGraphics
import AppKit
import os

let swipeLog = Logger(subsystem: "io.github.kkkevinky.tapper", category: "swipe")

// MARK: - Detection

/// Recognizes a horizontal two-finger swipe from raw contacts. Pure value type
/// so it can be driven with recorded frames outside the app.
///
/// Uses raw contacts, not the resting-finger filter used for taps: a finger
/// that rested on the shell and then swipes together with another one is a
/// genuine swipe. A single moving finger next to a still one is not.
struct TwoFingerSwipeTracker {
    struct Contact {
        let id: Int32
        let state: Int32
        let x: Float
        let y: Float
    }

    enum Event: Equatable {
        case began(travel: Float)
        case changed(travel: Float)
        /// `velocity` is the signed finger speed in surface widths per second.
        case ended(travel: Float, velocity: Float)
    }

    var startDistance: Float = 0.06
    /// The start distance has to be covered within this window, so slow drift
    /// of a resting finger never adds up to a swipe.
    var startWindow: TimeInterval = 0.3

    private var recent: [Int32: [(t: TimeInterval, x: Float, y: Float)]] = [:]
    private var baselines: [Int32: (x: Float, y: Float)] = [:]
    private var tracked: (Int32, Int32)?
    /// Fingers that already made a swipe in this touch: they cannot start
    /// another one until they lift, but other fingers can.
    private var spent = Set<Int32>()
    private var lastTravel: Float = 0
    private var history: [(t: TimeInterval, travel: Float)] = []

    private static func isTouching(_ state: Int32) -> Bool { (3...5).contains(state) }

    mutating func update(_ contacts: [Contact], now: TimeInterval) -> Event? {
        let touching = contacts.filter { Self.isTouching($0.state) }
        let present = Set(touching.map(\.id))
        spent = spent.intersection(present)
        recent = recent.filter { present.contains($0.key) }
        for contact in touching {
            var samples = recent[contact.id, default: []]
            samples.append((now, contact.x, contact.y))
            samples.removeAll { now - $0.t > startWindow }
            recent[contact.id] = samples
        }

        if let (a, b) = tracked {
            guard let ca = touching.first(where: { $0.id == a }),
                  let cb = touching.first(where: { $0.id == b }),
                  let ba = baselines[a], let bb = baselines[b] else {
                let velocity = currentVelocity()
                tracked = nil
                spent.formUnion([a, b].filter(present.contains))
                baselines.removeAll()
                history.removeAll()
                return .ended(travel: lastTravel, velocity: velocity)
            }
            let travel = ((ca.x - ba.x) + (cb.x - bb.x)) / 2
            lastTravel = travel
            history.append((now, travel))
            history.removeAll { now - $0.t > 0.08 }
            return .changed(travel: travel)
        }

        // Movement of each available finger over the recent window only.
        let moves = touching.compactMap { contact -> (id: Int32, dx: Float, dy: Float, x0: Float, y0: Float)? in
            guard !spent.contains(contact.id), let oldest = recent[contact.id]?.first else { return nil }
            return (contact.id, contact.x - oldest.x, contact.y - oldest.y, oldest.x, oldest.y)
        }
        guard moves.count >= 2 else { return nil }
        let leftward = moves.filter { $0.dx < 0 }.sorted { $0.dx < $1.dx }
        let rightward = moves.filter { $0.dx > 0 }.sorted { $0.dx > $1.dx }
        let group = abs(leftward.prefix(2).reduce(0) { $0 + $1.dx }) >= rightward.prefix(2).reduce(0) { $0 + $1.dx }
            ? leftward : rightward
        guard group.count >= 2 else { return nil }
        let first = group[0], second = group[1]
        let travel = (first.dx + second.dx) / 2
        let vertical = (abs(first.dy) + abs(second.dy)) / 2
        // Both fingers must move, mostly sideways.
        guard abs(travel) >= startDistance,
              min(abs(first.dx), abs(second.dx)) >= startDistance * 0.4,
              abs(travel) > vertical * 1.2 else { return nil }

        tracked = (first.id, second.id)
        baselines = [first.id: (first.x0, first.y0), second.id: (second.x0, second.y0)]
        lastTravel = travel
        history = [(now, travel)]
        return .began(travel: travel)
    }

    private func currentVelocity() -> Float {
        guard let first = history.first, let last = history.last, last.t > first.t else { return 0 }
        return (last.travel - first.travel) / Float(last.t - first.t)
    }

    mutating func reset() {
        recent.removeAll()
        baselines.removeAll()
        tracked = nil
        spent.removeAll()
        history.removeAll()
    }
}

// MARK: - Spaces

/// Read-only view of the Spaces on the display under the pointer, through the
/// private CGS calls also used by Mac Mouse Fix and InstantSpaceSwitcher. The
/// display and Space lookup is based on InstantSpaceSwitcher's.
struct SpaceLayout {
    let index: Int
    let count: Int
    let display: String

    private typealias MainConnection = @convention(c) () -> Int32
    private typealias GetActiveSpace = @convention(c) (Int32) -> UInt64
    private typealias CopyManagedDisplaySpaces = @convention(c) (Int32, CFString?) -> Unmanaged<CFArray>?

    private static let handle = UnsafeMutableRawPointer(bitPattern: -2) // RTLD_DEFAULT
    private static let mainConnection: MainConnection? = {
        guard let sym = dlsym(handle, "CGSMainConnectionID") ?? dlsym(handle, "_CGSDefaultConnection") else { return nil }
        return unsafeBitCast(sym, to: MainConnection.self)
    }()
    private static let getActiveSpace: GetActiveSpace? = {
        guard let sym = dlsym(handle, "CGSGetActiveSpace") else { return nil }
        return unsafeBitCast(sym, to: GetActiveSpace.self)
    }()
    private static let copyManagedDisplaySpaces: CopyManagedDisplaySpaces? = {
        guard let sym = dlsym(handle, "CGSCopyManagedDisplaySpaces") else { return nil }
        return unsafeBitCast(sym, to: CopyManagedDisplaySpaces.self)
    }()

    static func current(cursor: CGPoint?) -> SpaceLayout? {
        guard let mainConnection, let copyManagedDisplaySpaces,
              let displays = copyManagedDisplaySpaces(mainConnection(), nil)?.takeRetainedValue() as? [[String: Any]] else {
            return nil
        }
        let active = getActiveSpace?(mainConnection())

        var cursorUUID: String?
        var cursorIsMain = false
        if let cursor {
            var displayID: CGDirectDisplayID = 0
            var matches: UInt32 = 0
            if CGGetDisplaysWithPoint(cursor, 1, &displayID, &matches) == .success, matches > 0 {
                cursorIsMain = displayID == CGMainDisplayID()
                if let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() {
                    cursorUUID = CFUUIDCreateString(nil, uuid) as String
                }
            }
        }

        func spaceID(_ dict: [String: Any]?) -> UInt64? {
            (dict?["ManagedSpaceID"] as? NSNumber)?.uint64Value ?? (dict?["id64"] as? NSNumber)?.uint64Value
        }
        let display = displays.first { ($0["Display Identifier"] as? String) == cursorUUID }
            ?? displays.first { cursorIsMain && ($0["Display Identifier"] as? String) == "Main" }
            ?? displays.first { active != nil && spaceID($0["Current Space"] as? [String: Any]) == active }
        guard let display, let spaces = display["Spaces"] as? [[String: Any]],
              let currentID = spaceID(display["Current Space"] as? [String: Any]),
              let index = spaces.firstIndex(where: { spaceID($0) == currentID }) else {
            return nil
        }
        return SpaceLayout(index: index, count: spaces.count, display: display["Display Identifier"] as? String ?? "")
    }

    /// Dock progress for one Space on this display (Mac Mouse Fix and
    /// FasterSwiper both use n / (n - 1)).
    var unit: Double { count > 1 ? Double(count) / Double(count - 1) : 2.0 }
}

// MARK: - Output

/// Posts Dock swipe gesture events. On macOS 27 the Dock reads an IOHID payload
/// serialized into the CGEvent data instead of the plain gesture fields.
/// Adapted from InstantSpaceSwitcher (MIT, Copyright (c) 2026 jurplel),
/// Sources/ISS/ISS.c and Sources/ISS/event_serialize.c. Parts of its payload
/// serialization originate in FasterSwiper (Apache-2.0, Copyright 2026 Matthew
/// Bowen). Translated to Swift and modified; see THIRD_PARTY_NOTICES.md.
enum DockSwipePoster {
    enum Phase: Int64 { case began = 1, changed = 2, ended = 4, cancelled = 8 }

    struct Options {
        var payload: Bool
        var companion: Bool

        init(payload: Bool, companion: Bool) {
            self.payload = payload
            self.companion = companion
        }

        init(_ tuning: TouchTuning) {
            switch tuning.swipePayload {
            case "on": payload = true
            case "off": payload = false
            default: payload = DockSwipePoster.systemNeedsPayload
            }
            companion = tuning.swipeCompanion
        }
    }

    static let syntheticMarker: Int64 = 0x4D5453574950 // "MTSWIP"

    private static func field(_ raw: UInt32) -> CGEventField? { CGEventField(rawValue: raw) }

    /// Both the Foundation version and the kernel's product version, since a
    /// binary linked against an older SDK may be shown a compatibility version.
    static let detectedVersions: (foundation: Int, product: String) = {
        var buffer = [CChar](repeating: 0, count: 32)
        var size = buffer.count
        let product = sysctlbyname("kern.osproductversion", &buffer, &size, nil, 0) == 0 ? String(cString: buffer) : "?"
        return (ProcessInfo.processInfo.operatingSystemVersion.majorVersion, product)
    }()

    static let systemNeedsPayload: Bool = {
        let productMajor = Int(detectedVersions.product.split(separator: ".").first ?? "") ?? 0
        return max(detectedVersions.foundation, productMajor) >= 27
    }()

    @discardableResult
    static func post(phase: Phase, progress: Double, velocity: Double, options: Options) -> Bool {
        guard let event = CGEvent(source: nil), let type = field(55), let hidType = field(110),
              let phaseField = field(132), let motion = field(123), let progressField = field(124),
              let phaseAlias = field(134), let zoomDeltaY = field(138), let pidAlias = field(169),
              let positionX = field(125), let velocityX = field(129), let velocityY = field(130) else {
            return false
        }
        event.setIntegerValueField(type, value: 30)            // kCGSEventDockControl
        event.setIntegerValueField(hidType, value: 23)         // kIOHIDEventTypeDockSwipe
        event.setIntegerValueField(phaseField, value: phase.rawValue)
        event.setIntegerValueField(motion, value: 1)           // horizontal
        event.setDoubleValueField(progressField, value: progress)
        event.setIntegerValueField(phaseAlias, value: phase.rawValue)
        event.setDoubleValueField(zoomDeltaY, value: 3.0)
        event.setDoubleValueField(pidAlias, value: Double(mach_absolute_time()))
        event.setDoubleValueField(positionX, value: 0.1)
        if velocity != 0 {
            event.setDoubleValueField(velocityX, value: velocity)
            if !options.payload { event.setDoubleValueField(velocityY, value: velocity) }
        }
        event.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)

        let output: CGEvent
        if options.payload {
            guard let augmented = augment(event, phase: phase, progress: progress, velocity: velocity) else { return false }
            output = augmented
        } else {
            output = event
        }
        output.post(tap: .cgSessionEventTap)

        // The Dock ignores a DockControl event that arrives without a companion
        // gesture event (InstantSpaceSwitcher, macOS 27.0 release).
        if options.companion, let companion = CGEvent(source: nil) {
            companion.setIntegerValueField(type, value: 29)    // kCGSEventGesture
            companion.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)
            companion.post(tap: .cgSessionEventTap)
        }
        return true
    }

    private static func fixed1616(_ value: Double) -> Int32 {
        let clamped = max(-32767.0, min(32767.0, value))
        let fixed = Int32(clamped * 65536.0)
        if fixed == 0 && value != 0 { return value > 0 ? 1 : -1 }
        return fixed
    }

    private static func augment(_ event: CGEvent, phase: Phase, progress: Double, velocity: Double) -> CGEvent? {
        guard let data = event.data as Data?, data.count >= 4,
              data[data.startIndex] == 0, data[data.startIndex + 1] == 0,
              data[data.startIndex + 2] == 0, data[data.startIndex + 3] == 2 else {
            return nil
        }

        var payload = Data()
        func u8(_ v: UInt8) { payload.append(v) }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { payload.append(contentsOf: $0) } }
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { payload.append(contentsOf: $0) } }
        func i32(_ v: Int32) { withUnsafeBytes(of: v.littleEndian) { payload.append(contentsOf: $0) } }
        func u64(_ v: UInt64) { withUnsafeBytes(of: v.littleEndian) { payload.append(contentsOf: $0) } }

        let includeVelocity = velocity != 0 || phase == .ended
        // IOHIDSystemQueueElementHeader (28 bytes)
        u64(mach_absolute_time())       // timestamp
        u64(0)                          // sender id
        u32(0)                          // options
        u32(0)                          // attribute length
        u32(includeVelocity ? 2 : 1)    // event count
        // Dock swipe event (40 bytes)
        u32(40); u32(23); u32(UInt32(truncatingIfNeeded: (phase.rawValue & 0xFF) << 24))
        u8(0); u8(0); u8(0); u8(0)      // depth + reserved
        i32(fixed1616(0.1)); i32(0); i32(0)  // position x, y, z
        u32(0)                          // swipe mask
        u16(1)                          // motion: horizontal
        u16(3)                          // flavor: dock primary
        i32(fixed1616(progress))
        if includeVelocity {
            // Velocity child event (28 bytes, depth 1)
            u32(28); u32(9); u32(0)
            u8(1); u8(0); u8(0); u8(0)
            i32(fixed1616(velocity)); i32(0); i32(0)
        }

        var bytes = data
        let length = UInt16(payload.count)
        bytes.append(UInt8(length >> 8)); bytes.append(UInt8(length & 0xFF))
        bytes.append(UInt8(4205 >> 8)); bytes.append(UInt8(4205 & 0xFF))
        bytes.append(payload)
        return CGEvent(withDataAllocator: nil, data: bytes as CFData)
    }
}

/// Posts the Mission Control "Move left/right a space" shortcut with the
/// binding the user actually has (symbolic hot keys 79 and 81).
enum SpaceHotkeyPoster {
    private typealias IsEnabled = @convention(c) (Int32) -> Bool
    private typealias GetValue = @convention(c) (Int32, UnsafeMutablePointer<UInt16>?, UnsafeMutablePointer<UInt16>?, UnsafeMutablePointer<UInt32>?) -> Int32
    private static let handle = UnsafeMutableRawPointer(bitPattern: -2)

    static func post(toTheRight: Bool) -> Bool {
        guard let isEnabledSym = dlsym(handle, "CGSIsSymbolicHotKeyEnabled"),
              let getValueSym = dlsym(handle, "CGSGetSymbolicHotKeyValue") else { return false }
        let isEnabled = unsafeBitCast(isEnabledSym, to: IsEnabled.self)
        let getValue = unsafeBitCast(getValueSym, to: GetValue.self)
        let hotkey: Int32 = toTheRight ? 81 : 79
        guard isEnabled(hotkey) else {
            swipeLog.error("hotkey \(hotkey, privacy: .public) is disabled in Keyboard Shortcuts")
            return false
        }
        var character: UInt16 = 0, keyCode: UInt16 = 0
        var modifiers: UInt32 = 0
        guard getValue(hotkey, &character, &keyCode, &modifiers) == 0, keyCode != 0, keyCode != 0xFFFF,
              let down = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) else { return false }
        down.flags = CGEventFlags(rawValue: UInt64(modifiers))
        up.flags = CGEventFlags(rawValue: UInt64(modifiers))
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }
}

/// While a synthesized swipe is running, drops the scroll events the mouse
/// keeps emitting for the same finger movement (and their momentum tail), so
/// the window under the pointer does not scroll sideways during the switch.
final class SwipeScrollSuppressor: @unchecked Sendable {
    static let shared = SwipeScrollSuppressor()

    private let lock = NSLock()
    /// Active while the engine keeps refreshing it; expires on its own if
    /// touch frames ever stop, so scrolling can never stay blocked.
    private var activeUntil: TimeInterval = 0
    private var momentumUntil: TimeInterval = 0
    private var tap: CFMachPort?

    func refresh() {
        lock.lock()
        activeUntil = ProcessInfo.processInfo.systemUptime + 0.5
        lock.unlock()
    }

    func release() {
        lock.lock()
        activeUntil = 0
        momentumUntil = ProcessInfo.processInfo.systemUptime + 3.0
        lock.unlock()
    }

    private func shouldDrop(_ event: CGEvent) -> Bool {
        let now = ProcessInfo.processInfo.systemUptime
        let phase = event.getIntegerValueField(.scrollWheelEventScrollPhase)
        let momentum = event.getIntegerValueField(.scrollWheelEventMomentumPhase)
        lock.lock()
        defer { lock.unlock() }
        if now < activeUntil {
            // Let the app close the scroll gesture it already started.
            return !(phase == 4 || phase == 8)
        }
        if now < momentumUntil && momentum != 0 {
            if momentum == 3 { momentumUntil = 0; return false }   // momentum end
            return true
        }
        if phase == 1 { momentumUntil = 0 }                       // a new scroll began
        return false
    }

    /// Main thread only.
    func installIfNeeded() {
        guard tap == nil else { return }
        let mask = CGEventMask(1) << CGEventType.scrollWheel.rawValue
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let newTap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                             eventsOfInterest: mask, callback: { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let owner = Unmanaged<SwipeScrollSuppressor>.fromOpaque(context).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = owner.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                return Unmanaged.passUnretained(event)
            }
            return owner.shouldDrop(event) ? nil : Unmanaged.passUnretained(event)
        }, userInfo: context), let source = CFMachPortCreateRunLoopSource(nil, newTap, 0) else {
            swipeLog.error("scroll suppressor unavailable")
            return
        }
        tap = newTap
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)
    }
}

// MARK: - Engine

/// Turns two-finger swipes on the Magic Mouse into trackpad-style Space
/// switches. Runs on the multitouch touch queue.
final class SpaceSwipeEngine {
    private var tracker = TwoFingerSwipeTracker()
    private var tuning: TouchTuning
    private let cursor: () -> CGPoint?

    private struct DockGesture {
        let direction: Double        // sign of posted progress
        let fingerSign: Float        // sign of finger travel at the start
        let unit: Double             // progress for one Space
        let layout: SpaceLayout      // index is the effective one (prediction applied)
        let toTheRight: Bool
        let options: DockSwipePoster.Options
        var lastProgress: Double
        var lastPost: TimeInterval
    }

    private enum Gesture {
        case none
        case ignored
        /// Tracking the fingers but nothing posted yet: until the travel reaches
        /// swipeCommitDistance the swipe can still be abandoned silently,
        /// because every Dock gesture end switches the Space.
        case armed(toTheRight: Bool, fingerSign: Float, layout: SpaceLayout, options: DockSwipePoster.Options)
        case dock(DockGesture)
        /// stage 0: waiting for the distance; 1: began+changed posted, ended due
        /// on the next frame; 2: done for this touch.
        case instant(toTheRight: Bool, fingerSign: Float, layout: SpaceLayout, options: DockSwipePoster.Options, stage: Int)
        case hotkey(toTheRight: Bool, fingerSign: Float, fired: Bool)
    }
    private var gesture: Gesture = .none
    private var suppressingScroll = false
    /// Optional re-sent end events (Mac Mouse Fix, palmpad: WindowServer may drop
    /// the end under load). Off by default until shown not to switch again.
    /// Adapted from palmpad (MIT, Copyright (c) 2026 Xin), apple/Mac/Injector.swift.
    private var pendingEndResends: [DispatchWorkItem] = []
    /// The Space index CGS reports lags behind a running transition, so right
    /// after a switch the edge check also uses the predicted index
    /// (InstantSpaceSwitcher: pushing past the last Space can wedge the Dock).
    private var prediction: (display: String, index: Int, until: TimeInterval)?

    private var options: DockSwipePoster.Options
    private var systemSwipeCheckedAt: TimeInterval = -10
    private var systemSwipeOn = true

    init(tuning: TouchTuning, cursor: @escaping () -> CGPoint? = { CGEvent(source: nil)?.location }) {
        self.tuning = tuning
        self.cursor = cursor
        self.options = DockSwipePoster.Options(tuning)
        tracker.startDistance = tuning.swipeStartDistance
    }

    func update(tuning: TouchTuning) {
        self.tuning = tuning
        self.options = DockSwipePoster.Options(tuning)
        tracker.startDistance = tuning.swipeStartDistance
    }

    /// The native Magic Mouse full-screen swipe; when it is on, this engine
    /// stays out of the way so one swipe never switches twice.
    private func systemSwipeEnabled() -> Bool {
        let now = ProcessInfo.processInfo.systemUptime
        if now - systemSwipeCheckedAt > 2 {
            systemSwipeCheckedAt = now
            var values: [Int] = []
            for domain in ["com.apple.AppleMultitouchMouse", "com.apple.driver.AppleBluetoothMultitouch.mouse"] {
                CFPreferencesAppSynchronize(domain as CFString)
                if let number = CFPreferencesCopyAppValue("MouseTwoFingerHorizSwipeGesture" as CFString, domain as CFString) as? NSNumber {
                    values.append(number.intValue)
                }
            }
            // Absent means the driver default (on); any domain saying on wins.
            systemSwipeOn = values.isEmpty || values.contains { $0 != 0 }
        }
        return systemSwipeOn
    }

    private static func naturalScrolling() -> Bool {
        CFPreferencesAppSynchronize(kCFPreferencesAnyApplication)
        var valid: DarwinBoolean = false
        let natural = CFPreferencesGetAppBooleanValue("com.apple.swipescrolldirection" as CFString,
                                                      kCFPreferencesAnyApplication, &valid)
        return !valid.boolValue || natural
    }

    /// Sign of posted progress for a move toward the Space on the right.
    /// macOS 27: right is negative with natural scrolling on, and the Dock flips
    /// it again with natural scrolling off. Earlier systems: right is positive.
    /// Adapted from InstantSpaceSwitcher's iss_modern_swipe_sign.
    static func progressSign(toTheRight: Bool, options: DockSwipePoster.Options) -> Double {
        if options.payload {
            return (toTheRight ? -1 : 1) * (naturalScrolling() ? 1 : -1)
        }
        return toTheRight ? 1 : -1
    }

    /// The fingers have been recognized as a swipe, whether or not it posts
    /// anything, so they are not tapping.
    var isEngaged: Bool {
        if case .none = gesture { return false }
        return true
    }

    func process(_ contacts: [TwoFingerSwipeTracker.Contact], now: TimeInterval) {
        guard let event = tracker.update(contacts, now: now) else { return }
        switch event {
        case .began(let travel):
            begin(travel: travel, now: now)
        case .changed(let travel):
            change(travel: travel, now: now)
        case .ended(let travel, let velocity):
            end(travel: travel, velocity: velocity)
        }
    }

    /// Fingers moving left bring in the Space on the right, as on a trackpad.
    private func begin(travel: Float, now: TimeInterval) {
        pendingEndResends.forEach { $0.cancel() }
        pendingEndResends.removeAll()
        let mode = tuning.swipeMode
        guard mode == "dockswipe" || mode == "instant" || mode == "hotkey" else { gesture = .ignored; return }
        guard !systemSwipeEnabled() else {
            gesture = .ignored
            swipeLog.notice("swipe ignored: system two-finger swipe is on")
            return
        }
        let toTheRight = (travel < 0) != tuning.swipeInvert
        guard let layout = SpaceLayout.current(cursor: cursor()) else {
            gesture = .ignored
            swipeLog.error("swipe ignored: Space layout unavailable")
            return
        }
        var index = layout.index
        if let prediction, prediction.display == layout.display,
           ProcessInfo.processInfo.systemUptime < prediction.until {
            index = toTheRight ? max(index, prediction.index) : min(index, prediction.index)
        }
        if (toTheRight && index + 1 >= layout.count) || (!toTheRight && index == 0) {
            gesture = .ignored
            swipeLog.notice("swipe ignored: at edge (space \(index + 1, privacy: .public)/\(layout.count, privacy: .public))")
            return
        }
        // Base the next prediction on the effective index, not the lagging one.
        let base = SpaceLayout(index: index, count: layout.count, display: layout.display)
        let options = self.options
        if tuning.swipeSuppressScroll {
            SwipeScrollSuppressor.shared.refresh()
            suppressingScroll = true
            DispatchQueue.main.async { SwipeScrollSuppressor.shared.installIfNeeded() }
        }
        let fingerSign: Float = travel < 0 ? -1 : 1
        switch mode {
        case "hotkey":
            gesture = .hotkey(toTheRight: toTheRight, fingerSign: fingerSign, fired: false)
        case "instant":
            gesture = .instant(toTheRight: toTheRight, fingerSign: fingerSign, layout: base, options: options, stage: 0)
        default:
            gesture = .armed(toTheRight: toTheRight, fingerSign: fingerSign, layout: base, options: options)
        }
        change(travel: travel, now: now)
    }

    /// Progress stays on the gesture's side (moving back past the start gives
    /// zero, not the other way) and within one Space.
    private func progress(for travel: Float, _ g: DockGesture) -> Double {
        let along = Double(max(0, travel * g.fingerSign))
        return g.direction * min(max(along * tuning.swipeGain * g.unit, 1.0 / 65536.0), g.unit)
    }

    private func predictSwitch(_ layout: SpaceLayout, toTheRight: Bool) {
        prediction = (layout.display,
                      min(max(layout.index + (toTheRight ? 1 : -1), 0), layout.count - 1),
                      ProcessInfo.processInfo.systemUptime + 1.0)
    }

    private func change(travel: Float, now: TimeInterval) {
        if suppressingScroll { SwipeScrollSuppressor.shared.refresh() }
        switch gesture {
        case .armed(let toTheRight, let fingerSign, let layout, let options):
            guard travel * fingerSign >= tuning.swipeCommitDistance else { return }
            let direction = Self.progressSign(toTheRight: toTheRight, options: options)
            DockSwipePoster.post(phase: .began, progress: direction / 65536.0, velocity: 0, options: options)
            gesture = .dock(DockGesture(direction: direction, fingerSign: fingerSign, unit: layout.unit,
                                        layout: layout, toTheRight: toTheRight, options: options,
                                        lastProgress: 0, lastPost: -.infinity))
            swipeLog.notice("swipe began toward \(toTheRight ? "right" : "left", privacy: .public) space \(layout.index + 1, privacy: .public)/\(layout.count, privacy: .public)")
            change(travel: travel, now: now)
        case .dock(var g):
            let value = progress(for: travel, g)
            guard value != g.lastProgress, now - g.lastPost >= 0.008 else { return }
            DockSwipePoster.post(phase: .changed, progress: value, velocity: 0, options: g.options)
            g.lastProgress = value
            g.lastPost = now
            gesture = .dock(g)
        case .instant(let toTheRight, let fingerSign, let layout, let options, let stage):
            // Switch as soon as the fingers have travelled far enough toward the
            // target, without waiting for them to lift: began and changed now,
            // ended on the next frame (the spaced shape that was measured).
            if stage == 0 {
                guard travel * fingerSign >= tuning.swipeInstantDistance else { return }
                let direction = Self.progressSign(toTheRight: toTheRight, options: options)
                DockSwipePoster.post(phase: .began, progress: direction / 65536.0, velocity: 0, options: options)
                DockSwipePoster.post(phase: .changed, progress: direction * layout.unit * 0.5, velocity: 0, options: options)
                gesture = .instant(toTheRight: toTheRight, fingerSign: fingerSign, layout: layout, options: options, stage: 1)
            } else if stage == 1 {
                finishInstant(toTheRight: toTheRight, fingerSign: fingerSign, layout: layout, options: options)
            }
        case .hotkey(let toTheRight, let fingerSign, let fired):
            guard !fired, travel * fingerSign >= tuning.swipeHotkeyDistance else { return }
            let ok = SpaceHotkeyPoster.post(toTheRight: toTheRight)
            gesture = .hotkey(toTheRight: toTheRight, fingerSign: fingerSign, fired: true)
            swipeLog.notice("swipe hotkey toward \(toTheRight ? "right" : "left", privacy: .public) posted=\(ok, privacy: .public)")
        case .none, .ignored:
            break
        }
    }

    private func finishInstant(toTheRight: Bool, fingerSign: Float, layout: SpaceLayout, options: DockSwipePoster.Options) {
        let direction = Self.progressSign(toTheRight: toTheRight, options: options)
        DockSwipePoster.post(phase: .ended, progress: direction * layout.unit * 0.5,
                             velocity: direction * tuning.swipeInstantVelocity, options: options)
        predictSwitch(layout, toTheRight: toTheRight)
        gesture = .instant(toTheRight: toTheRight, fingerSign: fingerSign, layout: layout, options: options, stage: 2)
        swipeLog.notice("swipe instant toward \(toTheRight ? "right" : "left", privacy: .public) space \(layout.index + 1, privacy: .public)/\(layout.count, privacy: .public)")
    }

    /// On macOS 27.0.1 every synthesized end switches the Space whatever its
    /// progress or velocity, and a cancelled phase also switches and then leaves
    /// the Dock ignoring swipes for a few seconds (measured on this Mac). So the
    /// default closes every gesture with a plain ended toward the target.
    private static func postEnd(style: String, progress: Double, velocity: Double, direction: Double,
                                minVelocity: Double, options: DockSwipePoster.Options) {
        switch style {
        case "cancelled":
            DockSwipePoster.post(phase: .cancelled, progress: progress, velocity: velocity, options: options)
        case "ended0":
            DockSwipePoster.post(phase: .ended, progress: 0, velocity: 0, options: options)
        default:
            let toward = max(abs(velocity), minVelocity)
            DockSwipePoster.post(phase: .ended, progress: progress, velocity: direction * toward, options: options)
        }
    }

    private func end(travel: Float, velocity: Float) {
        defer {
            gesture = .none
            if suppressingScroll {
                SwipeScrollSuppressor.shared.release()
                suppressingScroll = false
            }
        }
        if case .instant(let toTheRight, let fingerSign, let layout, let options, 1) = gesture {
            finishInstant(toTheRight: toTheRight, fingerSign: fingerSign, layout: layout, options: options)
            return
        }
        if case .armed = gesture {
            swipeLog.notice("swipe abandoned before the commit distance")
            return
        }
        guard case .dock(let g) = gesture else { return }
        // Every end switches on 27.0.1, so never send one with almost no progress
        // (that shape once switched the wrong way).
        let value = g.direction * max(abs(progress(for: travel, g)), 0.15 * g.unit)
        // Release velocity in progress per second, in the posted progress space.
        let fingerAlong = Double(velocity * g.fingerSign)
        let progressVelocity = g.direction * max(fingerAlong, 0) * tuning.swipeGain * g.unit * tuning.swipeVelocityScale
        // "commit" (default) always switches; the other styles only apply when
        // the fingers were moving back at release (palmpad's "never mind").
        let takenBack = fingerAlong < 0 && tuning.swipeCancelStyle != "commit"
        let style = takenBack ? tuning.swipeCancelStyle : "commit"
        let options = g.options
        let direction = g.direction
        let minVelocity = tuning.swipeMinEndVelocity
        let ending = { Self.postEnd(style: style, progress: value, velocity: progressVelocity, direction: direction,
                                    minVelocity: minVelocity, options: options) }
        ending()
        // All measured end shapes switch, so always assume the switch happened.
        predictSwitch(g.layout, toTheRight: g.toTheRight)
        if tuning.swipeResendEnd {
            for delay in [0.2, 0.5] {
                let item = DispatchWorkItem(block: ending)
                pendingEndResends.append(item)
                DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: .now() + delay, execute: item)
            }
        }
        swipeLog.notice("swipe ended (\(style, privacy: .public)) progress=\(value / g.unit, format: .fixed(precision: 2), privacy: .public) velocity=\(progressVelocity, format: .fixed(precision: 2), privacy: .public)")
    }

    /// Ends an in-flight synthesized swipe (manager stop, sleep). A gesture left
    /// open can wedge the Dock, so it is closed the same way as a release.
    func cancel() {
        pendingEndResends.forEach { $0.cancel() }
        pendingEndResends.removeAll()
        if case .instant(let toTheRight, let fingerSign, let layout, let options, 1) = gesture {
            finishInstant(toTheRight: toTheRight, fingerSign: fingerSign, layout: layout, options: options)
        }
        if case .dock(let g) = gesture {
            Self.postEnd(style: "commit", progress: g.direction * max(abs(g.lastProgress), 0.15 * g.unit), velocity: 0,
                         direction: g.direction, minVelocity: tuning.swipeMinEndVelocity, options: g.options)
            predictSwitch(g.layout, toTheRight: g.toTheRight)
            swipeLog.notice("swipe closed by stop")
        }
        gesture = .none
        tracker.reset()
        if suppressingScroll {
            SwipeScrollSuppressor.shared.release()
            suppressingScroll = false
        }
    }
}

// MARK: - Debug command

/// Lets a developer replay a synthetic swipe from the shell while tuning:
/// only listens when `io.github.kkkevinky.tapper.tune.debugCommands` is true.
enum SwipeDebugCommand {
    static let name = Notification.Name("io.github.kkkevinky.tapper.debug.swipe")

    static func install() {
        guard UserDefaults.standard.bool(forKey: TouchTuning.defaultsPrefix + "debugCommands") else { return }
        DistributedNotificationCenter.default().addObserver(forName: name, object: nil, queue: nil) { note in
            guard UserDefaults.standard.bool(forKey: TouchTuning.defaultsPrefix + "debugCommands") else { return }
            let text = (note.object as? String) ?? ""
            var args: [String: String] = [:]
            for pair in text.split(separator: " ") {
                let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
                if parts.count == 2 { args[parts[0]] = parts[1] }
            }
            DispatchQueue.global(qos: .userInteractive).async { run(args) }
        }
        swipeLog.notice("debug swipe command listening")
    }

    private static func run(_ args: [String: String]) {
        let toTheRight = args["dir"] != "left"
        let target = min(max(Double(args["progress"] ?? "0.6") ?? 0.6, 0.01), 1.0)   // in Spaces
        let velocity = Double(args["velocity"] ?? "3") ?? 3          // progress per second
        let steps = Int(args["steps"] ?? "12") ?? 12
        let commit = args["end"] == nil || args["end"] == "ended"
        var options = DockSwipePoster.Options(TouchTuning.load())
        if let value = args["companion"] { options.companion = value == "1" }
        if let value = args["payload"] { options.payload = value == "1" }
        guard let layout = SpaceLayout.current(cursor: CGEvent(source: nil)?.location) else {
            swipeLog.error("debug swipe: no layout"); return
        }
        if (toTheRight && layout.index + 1 >= layout.count) || (!toTheRight && layout.index == 0) {
            swipeLog.notice("debug swipe: at edge \(layout.index + 1, privacy: .public)/\(layout.count, privacy: .public)"); return
        }
        let direction = SpaceSwipeEngine.progressSign(toTheRight: toTheRight, options: options)
        if args["lone"] == "1" {
            // Only an ended event, no began/changed: does a stray end switch?
            DockSwipePoster.post(phase: .ended, progress: direction * layout.unit * target, velocity: direction * velocity, options: options)
            swipeLog.notice("debug swipe posted lone ended")
            return
        }
        swipeLog.notice("debug swipe start payload=\(options.payload, privacy: .public) companion=\(options.companion, privacy: .public) dir=\(toTheRight ? "right" : "left", privacy: .public) target=\(target, privacy: .public) velocity=\(velocity, privacy: .public) space \(layout.index + 1, privacy: .public)/\(layout.count, privacy: .public)")
        DockSwipePoster.post(phase: .began, progress: direction / 65536.0, velocity: 0, options: options)
        for step in 1...max(1, steps) {
            Thread.sleep(forTimeInterval: 0.012)
            DockSwipePoster.post(phase: .changed, progress: direction * layout.unit * target * Double(step) / Double(steps), velocity: 0, options: options)
        }
        Thread.sleep(forTimeInterval: 0.012)
        let final = direction * layout.unit * target
        if commit {
            DockSwipePoster.post(phase: .ended, progress: final, velocity: direction * velocity, options: options)
        } else if args["end"] == "ended0" {
            DockSwipePoster.post(phase: .ended, progress: 0, velocity: 0, options: options)
        } else if args["end"] == "cancelv" {
            DockSwipePoster.post(phase: .cancelled, progress: final, velocity: -direction * velocity, options: options)
        } else {
            DockSwipePoster.post(phase: .cancelled, progress: final, velocity: 0, options: options)
        }
        if args["resend"] == "1" {
            for delay in [0.2, 0.5] {
                Thread.sleep(forTimeInterval: delay == 0.2 ? 0.2 : 0.3)
                if commit {
                    DockSwipePoster.post(phase: .ended, progress: final, velocity: direction * velocity, options: options)
                }
            }
            swipeLog.notice("debug swipe resent end twice")
        }
        swipeLog.notice("debug swipe posted end=\(args["end"] ?? "ended", privacy: .public)")
    }
}
