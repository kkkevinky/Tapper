import Foundation
import CoreGraphics

/// Configuration for tap detection and gesture recognition
/// All values can be persisted via UserDefaults through ConfigurationManager
struct TapConfiguration: Codable, Equatable {

    // MARK: - TapDetector Parameters

    /// Maximum duration for a tap to be recognized as a click (seconds)
    var tapTimeThreshold: TimeInterval

    /// Maximum cursor movement allowed during a tap (pixels)
    var tapMovementThreshold: CGFloat

    /// Minimum hold duration to trigger right-click (seconds)
    var rightClickTimeThreshold: TimeInterval

    /// Time window for double-tap detection (seconds)
    var doubleTapTimeWindow: TimeInterval

    /// Minimum tap duration to filter out noise (seconds)
    var minTapDuration: TimeInterval

    /// Movement threshold for drag debouncing (pixels)
    var dragThreshold: CGFloat

    /// Time threshold for quick tap detection (seconds)
    var quickTapThreshold: TimeInterval

    // MARK: - MultitouchManager Parameters

    /// X position threshold for right-click area (0.0-1.0, normalized)
    var rightClickAreaThreshold: Float

    /// Surface movement threshold to cancel tap (0.0-1.0, normalized)
    var surfaceMovementThreshold: Float

    /// Cumulative surface path length that cancels a tap (0.0-1.0 normalized).
    /// Unlike displacement, total travel cannot be hidden by sliding back to
    /// the start point, so it catches rubs and aborted scrolls.
    var surfacePathThreshold: Float

    /// Surface speed above which a touch is treated as scrolling and cancelled
    /// (normalized units/second). Scrolls are fast; tap jitter is not.
    var scrollVelocityThreshold: Float

    /// Time threshold for quick touch detection (seconds)
    var quickTouchTimeThreshold: TimeInterval

    // MARK: - Two-finger Zoom

    var zoomEnabled: Bool
    var zoomReversed: Bool
    var zoomSensitivity: Double

    // MARK: - Default Configuration

    /// Default configuration with optimized values
    static let `default` = TapConfiguration(
        // TapDetector defaults (current optimized values)
        tapTimeThreshold: 0.35,
        tapMovementThreshold: 8.0,
        // 0.1s sat inside the natural duration of a deliberate click, so
        // ordinary clicks on the right half were misread as right-clicks.
        rightClickTimeThreshold: 0.16,
        doubleTapTimeWindow: 0.3,
        minTapDuration: 0.03,
        dragThreshold: 2.0,
        quickTapThreshold: 0.15,
        // MultitouchManager defaults
        rightClickAreaThreshold: 0.6,
        surfaceMovementThreshold: 0.04,
        surfacePathThreshold: 0.10,
        scrollVelocityThreshold: 1.0,
        quickTouchTimeThreshold: 0.15
    )

    // MARK: - Initialization

    init(
        tapTimeThreshold: TimeInterval = 0.35,
        tapMovementThreshold: CGFloat = 8.0,
        rightClickTimeThreshold: TimeInterval = 0.16,
        doubleTapTimeWindow: TimeInterval = 0.3,
        minTapDuration: TimeInterval = 0.03,
        dragThreshold: CGFloat = 2.0,
        quickTapThreshold: TimeInterval = 0.15,
        rightClickAreaThreshold: Float = 0.6,
        surfaceMovementThreshold: Float = 0.04,
        surfacePathThreshold: Float = 0.10,
        scrollVelocityThreshold: Float = 1.0,
        quickTouchTimeThreshold: TimeInterval = 0.15,
        zoomEnabled: Bool = false,
        zoomReversed: Bool = false,
        zoomSensitivity: Double = 1
    ) {
        self.tapTimeThreshold = tapTimeThreshold
        self.tapMovementThreshold = tapMovementThreshold
        self.rightClickTimeThreshold = rightClickTimeThreshold
        self.doubleTapTimeWindow = doubleTapTimeWindow
        self.minTapDuration = minTapDuration
        self.dragThreshold = dragThreshold
        self.quickTapThreshold = quickTapThreshold
        self.rightClickAreaThreshold = rightClickAreaThreshold
        self.surfaceMovementThreshold = surfaceMovementThreshold
        self.surfacePathThreshold = surfacePathThreshold
        self.scrollVelocityThreshold = scrollVelocityThreshold
        self.quickTouchTimeThreshold = quickTouchTimeThreshold
        self.zoomEnabled = zoomEnabled
        self.zoomReversed = zoomReversed
        self.zoomSensitivity = zoomSensitivity.isFinite ? min(2, max(0.5, zoomSensitivity)) : 1
    }

    /// Tolerant decoding: configurations persisted by older app versions lack
    /// the newer keys. Decoding each key with a fallback keeps those users'
    /// custom values instead of silently resetting everything to defaults.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = TapConfiguration.default

        tapTimeThreshold = try container.decodeIfPresent(TimeInterval.self, forKey: .tapTimeThreshold) ?? fallback.tapTimeThreshold
        tapMovementThreshold = try container.decodeIfPresent(CGFloat.self, forKey: .tapMovementThreshold) ?? fallback.tapMovementThreshold
        rightClickTimeThreshold = try container.decodeIfPresent(TimeInterval.self, forKey: .rightClickTimeThreshold) ?? fallback.rightClickTimeThreshold
        doubleTapTimeWindow = try container.decodeIfPresent(TimeInterval.self, forKey: .doubleTapTimeWindow) ?? fallback.doubleTapTimeWindow
        minTapDuration = try container.decodeIfPresent(TimeInterval.self, forKey: .minTapDuration) ?? fallback.minTapDuration
        dragThreshold = try container.decodeIfPresent(CGFloat.self, forKey: .dragThreshold) ?? fallback.dragThreshold
        quickTapThreshold = try container.decodeIfPresent(TimeInterval.self, forKey: .quickTapThreshold) ?? fallback.quickTapThreshold
        rightClickAreaThreshold = try container.decodeIfPresent(Float.self, forKey: .rightClickAreaThreshold) ?? fallback.rightClickAreaThreshold
        surfaceMovementThreshold = try container.decodeIfPresent(Float.self, forKey: .surfaceMovementThreshold) ?? fallback.surfaceMovementThreshold
        surfacePathThreshold = try container.decodeIfPresent(Float.self, forKey: .surfacePathThreshold) ?? fallback.surfacePathThreshold
        scrollVelocityThreshold = try container.decodeIfPresent(Float.self, forKey: .scrollVelocityThreshold) ?? fallback.scrollVelocityThreshold
        quickTouchTimeThreshold = try container.decodeIfPresent(TimeInterval.self, forKey: .quickTouchTimeThreshold) ?? fallback.quickTouchTimeThreshold
        zoomEnabled = try container.decodeIfPresent(Bool.self, forKey: .zoomEnabled) ?? false
        zoomReversed = try container.decodeIfPresent(Bool.self, forKey: .zoomReversed) ?? false
        let sensitivity = try container.decodeIfPresent(Double.self, forKey: .zoomSensitivity) ?? 1
        zoomSensitivity = sensitivity.isFinite ? min(2, max(0.5, sensitivity)) : 1
    }
}

/// Manages tap configuration persistence and access
@MainActor
final class ConfigurationManager {

    // MARK: - Singleton

    static let shared = ConfigurationManager()

    // MARK: - Constants

    private let userDefaultsKey = "io.github.kkkevinky.tapper.tapConfiguration"

    // MARK: - Properties

    /// Current configuration (cached for performance)
    private(set) var current: TapConfiguration

    /// Notification posted when configuration changes
    static let configurationDidChangeNotification = Notification.Name("ConfigurationDidChange")

    // MARK: - Initialization

    private init() {
        // Load saved configuration or use defaults
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let saved = try? JSONDecoder().decode(TapConfiguration.self, from: data) {
            self.current = saved
            #if DEBUG
            print("📋 Loaded saved configuration")
            #endif
        } else {
            self.current = .default
            #if DEBUG
            print("📋 Using default configuration")
            #endif
        }
    }

    // MARK: - Public Methods

    /// Updates the configuration and persists to UserDefaults
    func update(_ configuration: TapConfiguration) {
        guard configuration != current else { return }

        current = configuration
        save()

        // Post notification for observers
        NotificationCenter.default.post(
            name: Self.configurationDidChangeNotification,
            object: self,
            userInfo: ["configuration": configuration]
        )

        #if DEBUG
        print("📋 Configuration updated and saved")
        #endif
    }

    /// Updates a single value in the configuration
    func update<T>(_ keyPath: WritableKeyPath<TapConfiguration, T>, to value: T) {
        var newConfig = current
        newConfig[keyPath: keyPath] = value
        update(newConfig)
    }

    /// Resets configuration to default values
    func resetToDefaults() {
        update(.default)
        #if DEBUG
        print("📋 Configuration reset to defaults")
        #endif
    }

    /// Checks if current configuration differs from defaults
    var hasCustomConfiguration: Bool {
        return current != .default
    }

    // MARK: - Private Methods

    private func save() {
        if let data = try? JSONEncoder().encode(current) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }
}
