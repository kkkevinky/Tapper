import Foundation
import CoreGraphics
import AppKit
import IOKit
import os

let tapLog = Logger(subsystem: "io.github.kkkevinky.tapper", category: "tap")

// Swift wrapper for Multitouch framework
final class MultitouchManager: @unchecked Sendable {
    private var devices: [MTDeviceRef] = []
    private var tapDetector: TapDetector
    private var isEnabled = true // Tap-to-click only; zoom is independent.
    private let zoomCoordinator: ZoomCoordinator
    private var tapDevice: Int32?
    private var consumedDevices = Set<Int32>()
    private var touchGeneration: UInt = 0
    private var activeTouch: Int32 = -1
    private var touchStartX: Float = 0.0
    private var touchStartY: Float = 0.0
    private var touchStartTime: CFAbsoluteTime = 0  // Use CFAbsoluteTime for better performance
    private var isDraggingActive = false  // Track if we're in drag mode
    private var isCancelled = false  // 当前触摸是否已取消（用于防止取消后的误触）
    private var pressBaselineUptime: TimeInterval = 0  // Monotonic; when the surface stopped being empty
    private var lastCursorLocation: CGPoint = .zero  // Cache cursor location
    private var touchStartCursorLocation: CGPoint = .zero

    // Resting fingers and light taps (see TouchTuning).
    private var tuning = TouchTuning.load()
    private var restingFilters: [Int32: RestingContactFilter] = [:]
    private var palmFilters: [Int32: PalmContactFilter] = [:]
    private var twoFingerTaps: [Int32: TwoFingerTapDetector] = [:]
    private var tapTimeLimit: TimeInterval
    private var activeTouchStartUptime: TimeInterval = 0
    private var activeTouchReachedTouching = false
    private var activeTouchMaxSize: Float = 0
    /// The tracked contact has qualified as a tap candidate (touchBegan called).
    private var activeTouchBegun = false
    private var cancelReason: String?
    private let swipeEngine: SpaceSwipeEngine
    private var configSummary = ""

    /// Injected so a frame-replay harness can run the decision logic without
    /// reading or posting real input.
    var cursorProvider: () -> CGPoint? = { CGEvent(source: nil)?.location }
    var hardwarePressCheck: (_ contactDuration: TimeInterval) -> Bool = MultitouchManager.physicalButtonPressed(within:)

    // Scroll-intent tracking. Displacement from the touch-start point can be
    // fooled by a finger that slides out and back (an aborted scroll or an
    // unconscious rub), so we additionally accumulate the total surface path
    // and watch the reported finger velocity — both are strong scroll signals
    // that a genuine tap never produces.
    private var lastSurfaceX: Float = 0.0
    private var lastSurfaceY: Float = 0.0
    private var surfacePathLength: Float = 0.0

    // Configuration-driven thresholds
    private var rightClickThreshold: Float      // X > threshold = right side
    private var surfaceMovementThreshold: Float // 表面移动阈值（用于检测滚动意图）
    private var surfacePathThreshold: Float     // 累积路程阈值（归一化，超出即判定为滑动）
    private var scrollVelocityThreshold: Float  // 表面速度阈值（归一化单位/秒，超出即判定为滚动）
    private var quickTouchTimeThreshold: TimeInterval // 快速触控时间阈值

    // Singleton access guarded by a lock: the C touch callback fires on an
    // arbitrary framework thread while init/deinit run on the main thread.
    private final class SharedStorage: @unchecked Sendable {
        let lock = NSLock()
        var instance: MultitouchManager?
    }

    private static let sharedStorage = SharedStorage()
    fileprivate static var sharedInstance: MultitouchManager? {
        sharedStorage.lock.lock()
        defer { sharedStorage.lock.unlock() }
        return sharedStorage.instance
    }
    fileprivate static func setSharedInstance(_ manager: MultitouchManager?) {
        sharedStorage.lock.lock()
        defer { sharedStorage.lock.unlock() }
        sharedStorage.instance = manager
    }
    fileprivate static func clearSharedInstanceIfMatching(_ candidate: MultitouchManager) {
        sharedStorage.lock.lock()
        defer { sharedStorage.lock.unlock() }
        if sharedStorage.instance === candidate {
            sharedStorage.instance = nil
        }
    }

    private let touchQueue = DispatchQueue(label: "io.github.kkkevinky.tapper.multitouch")
    private let touchQueueKey = DispatchSpecificKey<Void>()

    // Guards the critical section where the framework callback copies touch data
    // out of the (transient) C pointer. stop() takes the same lock while
    // unregistering/releasing devices, so an in-flight callback can never read
    // a dangling pointer.
    fileprivate let callbackLock = NSLock()
    fileprivate var isStopped = false

    var onClickSynthesized: ((CGPoint, Bool, Int) -> Void)?
    var onDragStarted: ((CGPoint) -> Void)?
    var onDragMoved: ((CGPoint) -> Void)?
    var onDragEnded: ((CGPoint) -> Void)?

    @MainActor
    init(zoomCoordinator: ZoomCoordinator) {
        self.zoomCoordinator = zoomCoordinator
        // Load configuration
        let config = ConfigurationManager.shared.current

        // Initialize TapDetector with configuration
        self.tapDetector = TapDetector(configuration: config)

        // Set MultitouchManager-specific thresholds
        self.rightClickThreshold = config.rightClickAreaThreshold
        self.surfaceMovementThreshold = config.surfaceMovementThreshold
        self.surfacePathThreshold = config.surfacePathThreshold
        self.scrollVelocityThreshold = config.scrollVelocityThreshold
        self.quickTouchTimeThreshold = config.quickTouchTimeThreshold
        self.tapTimeLimit = config.tapTimeThreshold
        self.swipeEngine = SpaceSwipeEngine(tuning: TouchTuning.load())
        self.configSummary = Self.summary(of: config)

        MultitouchManager.setSharedInstance(self)
        touchQueue.setSpecific(key: touchQueueKey, value: ())

        // Listen for configuration changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(configurationDidChange),
            name: ConfigurationManager.configurationDidChangeNotification,
            object: nil
        )
    }

    @objc private func configurationDidChange(_ notification: Notification) {
        guard let config = notification.userInfo?["configuration"] as? TapConfiguration else { return }

        performOnTouchQueue {
            zoomCoordinator.cancel()
            // Update TapDetector
            tapDetector.updateConfiguration(config)

            // Update MultitouchManager thresholds
            rightClickThreshold = config.rightClickAreaThreshold
            surfaceMovementThreshold = config.surfaceMovementThreshold
            surfacePathThreshold = config.surfacePathThreshold
            scrollVelocityThreshold = config.scrollVelocityThreshold
            quickTouchTimeThreshold = config.quickTouchTimeThreshold
            tapTimeLimit = config.tapTimeThreshold
            configSummary = Self.summary(of: config)
            tuning = TouchTuning.load()
            swipeEngine.update(tuning: tuning)
            twoFingerTaps.removeAll()
        }

        #if DEBUG
        print("🔧 MultitouchManager: Configuration updated")
        #endif
    }

    @discardableResult
    func start() -> Int {
        return performOnTouchQueue {
            startOnTouchQueue()
        }
    }

    private func startOnTouchQueue() -> Int {
        callbackLock.lock()
        defer { callbackLock.unlock() }

        guard devices.isEmpty else {
            return devices.count
        }

        guard let deviceList = MTDeviceCreateList() else {
            return 0
        }

        let deviceArray = deviceList.takeRetainedValue() as NSArray
        let count = CFArrayGetCount(deviceArray)

        isStopped = false

        for i in 0..<count {
            let device = unsafeBitCast(CFArrayGetValueAtIndex(deviceArray, i), to: MTDeviceRef.self)

            if isSupportedMagicMouse(device) {
                // CFArrayGetValueAtIndex returns a *borrowed* reference whose
                // only owner is `deviceArray`, which is released the moment this
                // function returns. We hold these devices for the lifetime of the
                // manager, so we must take our own +1 retain — otherwise the
                // framework can free the device (e.g. when the Magic Mouse
                // disconnects on sleep) while we still point at it, and the next
                // MTDeviceStop/MTDeviceRelease crashes (use-after-free / over-release).
                // Balanced by MTDeviceRelease in stop(). MTDeviceRef is a CFType
                // (its release path is CFRelease), so CFRetain is the correct +1.
                _ = Unmanaged<AnyObject>.fromOpaque(device).retain()
                devices.append(device)
                MTRegisterContactFrameCallback(device, touchCallback)
                MTDeviceStart(device, 0)
            }
        }

        NSLog("Tapper registered %d supported Magic Mouse device(s)", devices.count)
        let versions = DockSwipePoster.detectedVersions
        tapLog.notice("started: \(self.devices.count, privacy: .public) Magic Mouse device(s); \(self.configSummary, privacy: .public); rightTap=\(self.tuning.rightTapEnabled, privacy: .public) twoFingerTap=\(self.tuning.twoFingerTapEnabled, privacy: .public) hoverTaps=\(self.tuning.hoverTapsEnabled, privacy: .public) restAge=\(self.tuning.restAge, privacy: .public); swipe=\(self.tuning.swipeMode, privacy: .public) gain=\(self.tuning.swipeGain, privacy: .public) payload=\(DockSwipePoster.Options(self.tuning).payload, privacy: .public) companion=\(self.tuning.swipeCompanion, privacy: .public); macOS foundation=\(versions.foundation, privacy: .public) product=\(versions.product, privacy: .public)")

        return devices.count
    }

    func stop() {
        performOnTouchQueue {
            callbackLock.lock()
            defer { callbackLock.unlock() }

            // Mark stopped first so any in-flight callback bails out before
            // touching the (soon-to-be-released) device pointer.
            isStopped = true
            touchGeneration &+= 1
            zoomCoordinator.cancel(forgetContacts: true)
            tapDevice = nil
            consumedDevices.removeAll()
            cancelActiveGestureOnTouchQueue()
            swipeEngine.cancel()
            restingFilters.removeAll()
            palmFilters.removeAll()
            twoFingerTaps.removeAll()

            for device in devices {
                MTUnregisterContactFrameCallback(device, touchCallback)
                MTDeviceStop(device)
                MTDeviceRelease(device)
            }
            devices.removeAll()

        }
    }

    func setEnabled(_ enabled: Bool) {
        performOnTouchQueue {
            if isEnabled && !enabled {
                cancelActiveGestureOnTouchQueue()
                twoFingerTaps.removeAll()
            }
            isEnabled = enabled
        }
    }

    /// Returns the current number of registered devices
    func getDeviceCount() -> Int {
        return performOnTouchQueue {
            devices.count
        }
    }

    /// Check if devices are still valid and responding
    func validateDevices() -> Bool {
        return performOnTouchQueue {
            validateDevicesOnTouchQueue()
        }
    }

    private func validateDevicesOnTouchQueue() -> Bool {
        guard !devices.isEmpty else { return false }

        // Try to get fresh device list and compare
        guard let deviceList = MTDeviceCreateList() else { return false }

        let deviceArray = deviceList.takeRetainedValue() as NSArray
        let count = CFArrayGetCount(deviceArray)

        var currentDeviceIDs = Set<UInt64>()
        for i in 0..<count {
            let device = unsafeBitCast(CFArrayGetValueAtIndex(deviceArray, i), to: MTDeviceRef.self)
            if isSupportedMagicMouse(device), let deviceID = stableDeviceID(for: device) {
                currentDeviceIDs.insert(deviceID)
            }
        }

        let registeredDeviceIDs = Set(devices.compactMap { stableDeviceID(for: $0) })
        return registeredDeviceIDs.count == devices.count &&
               !registeredDeviceIDs.isEmpty &&
               registeredDeviceIDs == currentDeviceIDs
    }

    /// Called from the MultitouchSupport callback thread.
    /// The touches pointer is only valid for the duration of the callback, so
    /// the caller must have already copied it into `touches`. We dispatch
    /// async to `touchQueue` so the framework thread is never blocked.
    func enqueueTouches(_ touches: [MTTouch], device: Int32, timestamp: Double,
                        generation: UInt, zoomGeneration: UInt) {
        touchQueue.async { [weak self] in
            guard let self, !self.isStopped, self.touchGeneration == generation else { return }
            self.processTouchesOnTouchQueue(touches, device: device, timestamp: timestamp,
                                            zoomGeneration: zoomGeneration)
        }
    }

    /// Feeds one recorded frame through the same path as the framework callback.
    /// For a replay harness; the app itself never calls it.
    func replayFrame(_ touches: [MTTouch], device: Int32, timestamp: Double) {
        performOnTouchQueue {
            processTouchesOnTouchQueue(touches, device: device, timestamp: timestamp,
                                       zoomGeneration: zoomCoordinator.currentGeneration)
        }
    }

    // Read only under callbackLock, like the C buffer lifetime and stopped flag.
    fileprivate var callbackGeneration: UInt { touchGeneration }
    fileprivate var zoomGeneration: UInt { zoomCoordinator.currentGeneration }

    private func processTouchesOnTouchQueue(_ touches: [MTTouch], device: Int32,
                                            timestamp: Double, zoomGeneration: UInt) {
        // State 4 is touching; 7 is lingering/leaving and must not sustain zoom.
        // Keep the original frame for tap handling, preserving its existing ABI assumptions.
        // Palm and side-of-hand contacts are left out of taps and swipes.
        let palm = palmFilters[device, default: PalmContactFilter()].update(
            contacts: touches.map { (id: $0.identifier, y: $0.normalized.position.y, size: $0.size, major: $0.majorAxis) },
            tuning: tuning)

        // Swipe detection works on raw contacts (a finger that rested may join a
        // swipe) and on the frames' own timestamps, so release speed is not
        // skewed by queue delays.
        swipeEngine.process(touches.filter { !palm.swipe.contains($0.identifier) }.map {
            TwoFingerSwipeTracker.Contact(id: $0.identifier, state: $0.state,
                                          x: $0.normalized.position.x, y: $0.normalized.position.y)
        }, now: timestamp)

        // Resting fingers (a finger kept still on the shell while another one
        // taps) do not count as contacts for tap or zoom decisions. A finger in
        // the middle of a double-tap or drag never becomes resting.
        let holdsGesture = isDraggingActive || tapDetector.state == .secondTapPending
        let restingIDs = restingFilters[device, default: RestingContactFilter()].update(
            contacts: touches.map { (id: $0.identifier, x: $0.normalized.position.x, y: $0.normalized.position.y) },
            now: ProcessInfo.processInfo.systemUptime,
            restAge: max(tuning.restAge, tapTimeLimit + 0.1),
            restMove: tuning.restMove,
            exempt: holdsGesture ? activeTouch : nil)
        let effective = restingIDs.isEmpty && palm.tap.isEmpty ? touches
            : touches.filter { !restingIDs.contains($0.identifier) && !palm.tap.contains($0.identifier) }

        let zoomTouches = effective.filter { $0.state == 4 }.map {
            ZoomTouch(id: $0.identifier, x: Double($0.normalized.position.x),
                      y: Double($0.normalized.position.y))
        }
        ZoomDiagnostics.log("touch device=\(device) timestamp=\(timestamp) contacts=\(touches.map { "\($0.identifier):\($0.state):(\($0.normalized.position.x),\($0.normalized.position.y))" })")
        let target = zoomCoordinator.isEnabled && (zoomTouches.count == 2 || zoomCoordinator.needsTargetCheck)
            ? ZoomScrollFilter.currentTarget() : nil
        let zoomOwns = zoomCoordinator.process(device: device, touches: zoomTouches, timestamp: timestamp,
                                              dragging: isDraggingActive, generation: zoomGeneration,
                                              target: target, contactCount: effective.count)

        let numTouches = effective.count
        // Physical-press baseline: the first frame with a non-resting contact,
        // on a monotonic clock so wall-clock steps cannot move it.
        // Cleared on every frame without one, after the lift handling below.
        if numTouches > 0 && pressBaselineUptime == 0 {
            pressBaselineUptime = ProcessInfo.processInfo.systemUptime
        }
        defer { if numTouches == 0 { pressBaselineUptime = 0 } }
        // Every frame of a two-finger tap is consumed by the multi-contact
        // branch below, so it is followed and decided here.
        if isEnabled && tuning.twoFingerTapEnabled {
            processTwoFingerTapOnTouchQueue(touches, effective: effective, device: device, timestamp: timestamp)
        }
        if numTouches > 1 || zoomOwns {
            if !consumedDevices.contains(device) {
                let shapes = effective.map { String(format: "(%.2f,%.2f size %.2f major %.1f)", $0.normalized.position.x, $0.normalized.position.y, $0.size, $0.majorAxis) }.joined(separator: " ")
                tapLog.notice("consumed: \(numTouches, privacy: .public) moving contacts \(shapes, privacy: .public), \(restingIDs.count, privacy: .public) resting, \(palm.tap.count, privacy: .public) palm, zoom=\(zoomOwns, privacy: .public)")
            }
            consumedDevices.insert(device)
        }
        if consumedDevices.contains(device) {
            // Do not let a second device end another device's gesture.
            if tapDevice == nil || tapDevice == device {
                cancelActiveGestureOnTouchQueue()
                tapDevice = nil
            }
            if numTouches == 0 { consumedDevices.remove(device) }
            return
        }
        guard isEnabled else { return }
        if let tapDevice, tapDevice != device { return }
        if numTouches > 0 { tapDevice = device }
        defer { if numTouches == 0 { tapDevice = nil } }

        // Only fetch cursor position when needed (touch start, end, or drag)
        // For touch move without drag, we can skip this expensive call
        func getCursorLocation() -> CGPoint {
            if let location = cursorProvider() {
                lastCursorLocation = location
            }
            return lastCursorLocation
        }

        if numTouches == 0 {
            if activeTouch != -1 && !activeTouchBegun {
                // A faint contact that never qualified as a tap candidate.
                tapLog.notice("tap -> no click (contact never qualified: size \(self.activeTouchMaxSize, format: .fixed(precision: 2), privacy: .public))")
                activeTouch = -1
                isCancelled = false
                resetPerTouchStateOnTouchQueue()
                resetSurfaceTrackingOnTouchQueue()
            }
            if activeTouch != -1 {
                // Touch ended - need cursor position
                let cgLocation = getCursorLocation()

                // The finger is still on the surface: it came to rest instead of
                // lifting, which is never a tap.
                if !isCancelled && touches.contains(where: { $0.identifier == activeTouch }) {
                    cancelActiveTouchAsScrollOnTouchQueue(reason: palm.tap.contains(activeTouch) ? "palm contact" : "finger came to rest")
                }

                if !isCancelled && physicalButtonPressedDuringTouchOnTouchQueue() {
                    cancelActiveTouchAsScrollOnTouchQueue(reason: "physical press")
                }

                let contactDuration = ProcessInfo.processInfo.systemUptime - activeTouchStartUptime
                if !isCancelled && !activeTouchReachedTouching &&
                    (activeTouchMaxSize < tuning.hoverMinSize || contactDuration < tuning.hoverMinDuration) {
                    cancelActiveTouchAsScrollOnTouchQueue(reason: String(
                        format: "hover-only contact too faint (size %.2f, %.3fs)", self.activeTouchMaxSize, contactDuration))
                }

                let liftMove = hypot(cgLocation.x - touchStartCursorLocation.x, cgLocation.y - touchStartCursorLocation.y)
                let summary = String(format: "dur=%.3fs x=%.2f y=%.2f size=%.2f touching=%@ path=%.3f cursor=%.1fpx resting=%d palm=%d",
                                     contactDuration, touchStartX, touchStartY, activeTouchMaxSize,
                                     activeTouchReachedTouching ? "yes" : "hover-only", surfacePathLength,
                                     liftMove, restingIDs.count, palm.tap.count)

                // 如果触摸已被取消（表面移动检测触发），不处理点击
                if !isCancelled {
                    let isRightSide = tuning.rightTapEnabled && touchStartX > rightClickThreshold
                    let result = tapDetector.touchEnded(at: cgLocation, isRightSide: isRightSide)

                    // Handle click
                    if result.shouldClick, let clickLocation = result.clickLocation {
                        onClickSynthesized?(clickLocation, result.isRightClick, result.clickCount)
                        tapLog.notice("tap -> \(result.isRightClick ? "RIGHT" : "LEFT", privacy: .public) click x\(result.clickCount, privacy: .public) \(summary, privacy: .public)")
                    } else if !isDraggingActive {
                        tapLog.notice("tap -> no click (duration/cursor limits) \(summary, privacy: .public)")
                    }

                    // Handle drag end
                    if isDraggingActive {
                        onDragEnded?(cgLocation)
                        isDraggingActive = false
                    }
                } else {
                    tapLog.notice("tap -> no click (\(self.cancelReason ?? "cancelled", privacy: .public)) \(summary, privacy: .public)")
                    #if DEBUG
                    print("🚫 Touch ended but was cancelled - no click")
                    #endif
                    // 如果已取消且在拖拽，也要结束拖拽
                    if isDraggingActive {
                        onDragEnded?(cgLocation)
                        isDraggingActive = false
                    }
                }

                activeTouch = -1
                touchStartX = 0.0
                touchStartY = 0.0
                touchStartTime = 0
                touchStartCursorLocation = .zero
                isCancelled = false
                resetPerTouchStateOnTouchQueue()
                resetSurfaceTrackingOnTouchQueue()
            }
            return
        }

        if numTouches == 1 {
            let touch = effective[0]

            // Another finger took over without an empty frame in between: the
            // old touch can no longer be judged, so drop it and start fresh.
            if activeTouch != -1 && touch.identifier != activeTouch {
                tapLog.notice("tap -> no click (contact handed over to another finger)")
                cancelActiveGestureOnTouchQueue()
            }

            // Cancel as soon as the press is seen so it cannot turn into a
            // synthesized drag either.
            if activeTouch != -1 && !isCancelled && physicalButtonPressedDuringTouchOnTouchQueue() {
                cancelActiveTouchAsScrollOnTouchQueue(reason: "physical press")
                return
            }

            if acceptsTapState(touch.state) {
                if activeTouch == -1 {
                    // Track the contact from its first frame (for the hover gate)...
                    activeTouch = touch.identifier
                    activeTouchStartUptime = ProcessInfo.processInfo.systemUptime
                    activeTouchBegun = false
                    isCancelled = false
                }
                activeTouchReachedTouching = activeTouchReachedTouching || touch.state == 4
                activeTouchMaxSize = max(activeTouchMaxSize, touch.size)

                // ...but it only becomes a tap candidate once it really touches,
                // or is a light touch of meaningful size. Side, timing and the
                // double-tap window are taken from that moment.
                let qualifies = touch.state == 4 || touch.state == 7 ||
                    (tuning.hoverTapsEnabled && touch.size >= tuning.hoverMinSize)
                if !activeTouchBegun {
                    guard qualifies else { return }
                    activeTouchBegun = true
                    // New touch started - need cursor position
                    let cgLocation = getCursorLocation()

                    touchStartX = touch.normalized.position.x
                    touchStartY = touch.normalized.position.y
                    touchStartTime = CFAbsoluteTimeGetCurrent()
                    touchStartCursorLocation = cgLocation
                    lastSurfaceX = touchStartX
                    lastSurfaceY = touchStartY
                    surfacePathLength = 0.0

                    let isRightSide = tuning.rightTapEnabled && touchStartX > rightClickThreshold
                    _ = tapDetector.touchBegan(at: cgLocation, isRightSide: isRightSide)

                    if physicalButtonPressedDuringTouchOnTouchQueue() {
                        cancelActiveTouchAsScrollOnTouchQueue(reason: "physical press")
                    }

                } else if activeTouch == touch.identifier {
                    // Same touch continuing

                    // 仅在非拖拽状态下检查表面移动（拖拽时手指滑动是正常的）
                    if !isDraggingActive {
                        let positionX = touch.normalized.position.x
                        let positionY = touch.normalized.position.y

                        // 累积路程 + 速度：滚动意图的两个硬信号。
                        // 位移检测可以被"滑出去又滑回来"绕过，路程和速度不会。
                        surfacePathLength += hypotf(positionX - lastSurfaceX, positionY - lastSurfaceY)
                        lastSurfaceX = positionX
                        lastSurfaceY = positionY
                        let surfaceSpeed = hypotf(touch.normalized.velocity.x, touch.normalized.velocity.y)

                        if surfaceSpeed > scrollVelocityThreshold {
                            #if DEBUG
                            print("🚫 Scroll velocity detected: \(String(format: "%.3f", surfaceSpeed)) > \(String(format: "%.3f", scrollVelocityThreshold))")
                            #endif
                            cancelActiveTouchAsScrollOnTouchQueue(reason: String(format: "surface speed %.2f > %.2f", surfaceSpeed, scrollVelocityThreshold))
                            return
                        }

                        if surfacePathLength > surfacePathThreshold {
                            #if DEBUG
                            print("🚫 Surface path exceeded: \(String(format: "%.3f", surfacePathLength)) > \(String(format: "%.3f", surfacePathThreshold))")
                            #endif
                            cancelActiveTouchAsScrollOnTouchQueue(reason: String(format: "surface path %.3f > %.3f", surfacePathLength, surfacePathThreshold))
                            return
                        }

                        let deltaX = abs(positionX - touchStartX)
                        let deltaY = abs(positionY - touchStartY)
                        let surfaceMovement = max(deltaX, deltaY)

                        // 智能表面移动检测：
                        // - 快速触控（<0.15s）：允许更大的表面移动（防止快速点击被误判）
                        // - 慢速触控：严格检测表面移动（防止滚动误触）
                        let touchDuration = CFAbsoluteTimeGetCurrent() - touchStartTime
                        let isQuickTouch = touchDuration < quickTouchTimeThreshold
                        let effectiveThreshold = isQuickTouch ? surfaceMovementThreshold * 2.0 : surfaceMovementThreshold

                        if surfaceMovement > effectiveThreshold {
                            // Finger moved too much on surface - likely scrolling, cancel tap
                            #if DEBUG
                            print("🚫 Surface movement detected: \(String(format: "%.3f", surfaceMovement)) > \(String(format: "%.3f", effectiveThreshold)) (quick: \(isQuickTouch))")
                            #endif
                            cancelActiveTouchAsScrollOnTouchQueue(reason: String(format: "surface movement %.3f > %.3f", surfaceMovement, effectiveThreshold))
                            return
                        }

                        // Cursor displacement is part of tap validation. Passing the
                        // cached start location here would make the movement threshold
                        // ineffective until the touch ends.
                        let cgLocation = getCursorLocation()
                        let result = tapDetector.touchMoved(to: cgLocation)

                        // A second tap becomes a drag only after cursor movement
                        // crosses the tap movement threshold, and only for a finger
                        // that really touched: a hovering finger never holds the button.
                        if result.isDragging && !activeTouchReachedTouching {
                            cancelActiveTouchAsScrollOnTouchQueue(reason: "light touch cannot start a drag")
                            return
                        }
                        if result.isDragging {
                            isDraggingActive = true
                            onDragStarted?(touchStartCursorLocation)
                            if let dragLocation = result.dragLocation {
                                onDragMoved?(dragLocation)
                            }
                        }
                    } else {
                        // Dragging - need fresh cursor position
                        let cgLocation = getCursorLocation()
                        let result = tapDetector.touchMoved(to: cgLocation)

                        // Handle drag movement
                        if result.isDragging, let dragLocation = result.dragLocation {
                            onDragMoved?(dragLocation)
                        }
                    }
                }
            }
        }
    }

    private func isSupportedMagicMouse(_ device: MTDeviceRef) -> Bool {
        let descriptor = deviceDescriptor(for: device)
        let isSupported = MultitouchDeviceClassifier.isMagicMouse(descriptor)

        #if DEBUG
        print("🖱️ Multitouch device: builtIn=\(descriptor.isBuiltIn), opaque=\(descriptor.isOpaqueSurface), product=\(descriptor.productName ?? "unknown"), preferenceKeys=\(descriptor.preferenceKeys.sorted()), supported=\(isSupported)")
        #endif

        return isSupported
    }

    private func deviceDescriptor(for device: MTDeviceRef) -> MultitouchDeviceDescriptor {
        let isBuiltIn = MTDeviceIsBuiltIn(device)
        let isOpaqueSurface = MTDeviceIsOpaqueSurface(device)
        let service = MTDeviceGetService(device)

        guard service != IO_OBJECT_NULL else {
            return MultitouchDeviceDescriptor(
                isBuiltIn: isBuiltIn,
                isOpaqueSurface: isOpaqueSurface,
                preferenceKeys: [],
                productName: nil
            )
        }

        var unmanagedProperties: Unmanaged<CFMutableDictionary>?
        let result = IORegistryEntryCreateCFProperties(
            service,
            &unmanagedProperties,
            kCFAllocatorDefault,
            0
        )

        guard result == KERN_SUCCESS,
              let properties = unmanagedProperties?.takeRetainedValue() as? [String: Any] else {
            return MultitouchDeviceDescriptor(
                isBuiltIn: isBuiltIn,
                isOpaqueSurface: isOpaqueSurface,
                preferenceKeys: [],
                productName: nil
            )
        }

        let preferences = properties["MultitouchPreferences"] as? [String: Any]
        return MultitouchDeviceDescriptor(
            isBuiltIn: isBuiltIn,
            isOpaqueSurface: isOpaqueSurface,
            preferenceKeys: Set(preferences?.keys.map { $0 } ?? []),
            productName: properties["Product"] as? String
        )
    }

    /// Two fingers tapped together: a right click at the pointer, as on a
    /// trackpad. Decided on the frame where the surface is empty again.
    private func processTwoFingerTapOnTouchQueue(_ touches: [MTTouch], effective: [MTTouch],
                                                 device: Int32, timestamp: Double) {
        var detector = twoFingerTaps[device, default: TwoFingerTapDetector()]
        defer { twoFingerTaps[device] = detector }

        if isDraggingActive { detector.cancel(reason: "drag in progress") }
        if swipeEngine.isEngaged { detector.cancel(reason: "swipe") }
        if zoomCoordinator.isZooming { detector.cancel(reason: "zoom") }
        // Gone from the effective contacts but still on the surface: the finger
        // came to rest or turned out to be a palm, which is never a tap.
        if effective.isEmpty && touches.contains(where: { detector.fingerIDs.contains($0.identifier) }) {
            detector.cancel(reason: "finger came to rest")
        }

        let limits = TwoFingerTapDetector.Limits(
            maxDuration: tapTimeLimit,
            minDuration: tapDetector.minTapDuration,
            maxFingerGap: tuning.twoFingerTapGap,
            maxSurfaceMovement: surfaceMovementThreshold,
            maxSurfacePath: surfacePathThreshold,
            maxCursorMovement: tapDetector.tapMovementThreshold,
            hoverTaps: tuning.hoverTapsEnabled,
            hoverMinSize: tuning.hoverMinSize,
            hoverMinDuration: tuning.hoverMinDuration)
        let contacts = effective.map {
            TwoFingerTapDetector.Contact(id: $0.identifier, state: $0.state, x: $0.normalized.position.x,
                                         y: $0.normalized.position.y, size: $0.size)
        }
        let outcome = detector.update(contacts, now: timestamp, limits: limits) {
            let location = cursorProvider()
            if let location { lastCursorLocation = location }
            return location
        }

        switch outcome {
        case .tap(let location, let summary)?:
            // Checked before posting, so our own right-down is never mistaken
            // for a press.
            if physicalButtonPressedDuringTouchOnTouchQueue() {
                tapLog.notice("two-finger tap -> no click (physical press) \(summary, privacy: .public)")
                return
            }
            onClickSynthesized?(location ?? lastCursorLocation, true, 1)
            tapLog.notice("two-finger tap -> RIGHT click \(summary, privacy: .public)")
        case .rejected(let reason, let summary)?:
            tapLog.notice("two-finger tap -> no click (\(reason, privacy: .public)) \(summary, privacy: .public)")
        case nil:
            break
        }
    }

    private func stableDeviceID(for device: MTDeviceRef) -> UInt64? {
        var deviceID: UInt64 = 0
        return MTDeviceGetDeviceID(device, &deviceID) == 0 ? deviceID : nil
    }

    private func cancelActiveGestureOnTouchQueue() {
        if isDraggingActive {
            let location: CGPoint
            if let event = CGEvent(source: nil) {
                lastCursorLocation = event.location
                location = event.location
            } else {
                location = lastCursorLocation
            }
            onDragEnded?(location)
        }

        tapDetector.reset()
        activeTouch = -1
        touchStartX = 0.0
        touchStartY = 0.0
        touchStartTime = 0
        touchStartCursorLocation = .zero
        isCancelled = false
        isDraggingActive = false
        resetPerTouchStateOnTouchQueue()
        resetSurfaceTrackingOnTouchQueue()
    }

    /// Marks the in-flight touch as a scroll/slide so lifting the finger
    /// cannot synthesize a click. The touch itself keeps being tracked so the
    /// same finger cannot restart a gesture mid-contact.
    private func cancelActiveTouchAsScrollOnTouchQueue(reason: @autoclosure () -> String) {
        tapDetector.reset()
        if !isCancelled { cancelReason = reason() }
        isCancelled = true
    }

    /// Touching (4) and leaving (7) always count; with hover taps on, the
    /// approach/hover/break states of a light tap count as well.
    private func acceptsTapState(_ state: Int32) -> Bool {
        if state == 4 || state == 7 { return true }
        return tuning.hoverTapsEnabled && (1...6).contains(state)
    }

    private static func summary(of config: TapConfiguration) -> String {
        String(format: "tap<%.2fs min %.2fs move %.0fpx doubleTap %.2fs surface %.3f/%.3f speed %.2f",
               config.tapTimeThreshold, config.minTapDuration, Double(config.tapMovementThreshold),
               config.doubleTapTimeWindow, config.surfaceMovementThreshold, config.surfacePathThreshold,
               config.scrollVelocityThreshold)
    }

    private func resetPerTouchStateOnTouchQueue() {
        activeTouchStartUptime = 0
        activeTouchReachedTouching = false
        activeTouchMaxSize = 0
        activeTouchBegun = false
        cancelReason = nil
    }

    /// A physical click is also a short, still, single contact, so without
    /// this check the hardware click would be followed by a synthesized one
    /// at lift. Checks both the live button state and whether any mouse-down
    /// arrived since the surface stopped being empty (a press can fall between
    /// two frames). Our own previous click is posted while handling the empty
    /// frame, before the baseline is taken, so it never counts.
    /// Skipped while dragging: the synthesized drag itself holds the button.
    private func physicalButtonPressedDuringTouchOnTouchQueue() -> Bool {
        guard !isDraggingActive, pressBaselineUptime > 0 else { return false }
        return hardwarePressCheck(ProcessInfo.processInfo.systemUptime - pressBaselineUptime)
    }

    static func physicalButtonPressed(within contactDuration: TimeInterval) -> Bool {
        let buttons: [CGMouseButton] = [.left, .right]
        if buttons.contains(where: { CGEventSource.buttonState(.hidSystemState, button: $0) }) {
            return true
        }
        let downTypes: [CGEventType] = [.leftMouseDown, .rightMouseDown]
        return downTypes.contains {
            CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: $0) < contactDuration
        }
    }

    private func resetSurfaceTrackingOnTouchQueue() {
        lastSurfaceX = 0.0
        lastSurfaceY = 0.0
        surfacePathLength = 0.0
    }

    deinit {
        stop()
        NotificationCenter.default.removeObserver(self)
        MultitouchManager.clearSharedInstanceIfMatching(self)
    }

    private func performOnTouchQueue<T>(_ work: () -> T) -> T {
        if DispatchQueue.getSpecific(key: touchQueueKey) != nil {
            return work()
        }

        return touchQueue.sync(execute: work)
    }
}

private func touchCallback(device: Int32, touches: UnsafeMutablePointer<MTTouch>?, numTouches: Int32, timestamp: Double, frame: Int32) -> Int32 {
    guard let manager = MultitouchManager.sharedInstance, numTouches >= 0,
          numTouches == 0 || touches != nil else {
        return 0
    }

    // Copy the touch data out of the transient C pointer under the manager's
    // callback lock. stop() takes the same lock while releasing devices, so
    // either we copy before stop() releases (safe) or we observe isStopped and
    // bail out without dereferencing the pointer (safe).
    let count = Int(numTouches)
    let buffer: [MTTouch]
    manager.callbackLock.lock()
    if manager.isStopped {
        manager.callbackLock.unlock()
        return 0
    }
    buffer = count > 0 ? Array(UnsafeBufferPointer(start: touches, count: count)) : []
    let generation = manager.callbackGeneration
    let zoomGeneration = manager.zoomGeneration
    manager.callbackLock.unlock()

    manager.enqueueTouches(buffer, device: device, timestamp: timestamp,
                           generation: generation, zoomGeneration: zoomGeneration)
    return 0
}
