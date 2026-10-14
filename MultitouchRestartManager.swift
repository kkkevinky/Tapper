import Foundation

/// Abstraction over the AppDelegate-owned multitouch lifecycle.
///
/// `MultitouchRestartManager` talks to this protocol instead of reaching into
/// `AppDelegate` internals, so the retry/backoff logic can be unit-tested with
/// a fake controller and no AppKit/Cocoa dependency.
@MainActor
protocol MultitouchController: AnyObject {
    /// Whether either touch feature is enabled and the system is awake.
    var isAppEnabled: Bool { get }

    /// Current number of active multitouch devices.
    var currentDeviceCount: Int { get }

    /// Whether the registered devices still match the currently connected devices.
    var areCurrentDevicesValid: Bool { get }

    /// Tear down the existing multitouch manager and create + start a fresh one.
    /// Returns the number of devices the new manager found.
    @discardableResult
    func stopAndRecreateMultitouch() -> Int
}

extension MultitouchController {
    var areCurrentDevicesValid: Bool {
        currentDeviceCount > 0
    }
}

/// Manages multitouch device restart with retry logic and health monitoring.
@MainActor
final class MultitouchRestartManager {

    // MARK: - Types

    struct RetryConfig {
        let maxAttempts: Int
        let initialDelay: TimeInterval
        let maxDelay: TimeInterval
        let backoffMultiplier: Double

        static let `default` = RetryConfig(
            maxAttempts: Constants.Retry.maxAttempts,
            initialDelay: Constants.Retry.initialDelay,
            maxDelay: Constants.Retry.maxDelay,
            backoffMultiplier: Constants.Retry.backoffMultiplier
        )

        /// Calculate delay for a given attempt (exponential backoff with cap)
        func delay(forAttempt attempt: Int) -> TimeInterval {
            let delay = initialDelay * pow(backoffMultiplier, Double(attempt - 1))
            return min(delay, maxDelay)
        }
    }

    enum RestartReason: String {
        case systemWake = "system_wake"
        case bluetoothReconnect = "bluetooth_reconnect"
        case healthCheck = "health_check"
        case manual = "manual"
    }

    /// Schedules a closure to run after a delay. Injectable for tests so the
    /// retry loop can be driven synchronously.
    typealias ScheduledWork = @MainActor @Sendable () -> Void
    typealias Scheduler = @MainActor (TimeInterval, @escaping ScheduledWork) -> Void

    static let defaultScheduler: Scheduler = { delay, work in
        if delay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        } else {
            work()
        }
    }

    // MARK: - Properties

    private weak var controller: MultitouchController?
    private let retryConfig: RetryConfig
    private let schedule: Scheduler
    private var currentAttempt = 0
    private var isRestarting = false
    private var restartGeneration: UInt = 0

    // Health check timer with adaptive interval
    private var healthCheckTimer: Timer?
    private(set) var currentHealthCheckInterval: TimeInterval = Constants.HealthCheck.defaultInterval
    private(set) var consecutiveSuccessfulChecks = 0

    // Track last successful device detection
    private(set) var lastSuccessfulStart: Date?
    private(set) var consecutiveFailures = 0

    // MARK: - Callbacks

    var onRestartCompleted: ((Bool, Int) -> Void)?  // (success, deviceCount)
    var onRestartFailed: ((Int) -> Void)?  // (attempts)

    // MARK: - Initialization

    init(controller: MultitouchController,
         config: RetryConfig = .default,
         schedule: Scheduler? = nil) {
        self.controller = controller
        self.retryConfig = config
        self.schedule = schedule ?? Self.defaultScheduler
    }

    deinit {
        healthCheckTimer?.invalidate()
    }

    // MARK: - Public Methods

    /// Restart multitouch manager with retry logic
    func restart(reason: RestartReason, afterDelay initialDelay: TimeInterval = 0) {
        // Cancel any pending restart
        cancelPendingRestart()

        // Reset state for new restart sequence
        currentAttempt = 0
        isRestarting = true
        let generation = restartGeneration

        #if DEBUG
        print("🔄 MultitouchRestartManager: Starting restart sequence (reason: \(reason.rawValue))")
        #endif

        if initialDelay > 0 {
            schedule(initialDelay) { [weak self] in
                guard let self = self,
                      self.isRestarting,
                      self.restartGeneration == generation else { return }
                self.performRestart(reason: reason, generation: generation)
            }
        } else {
            performRestart(reason: reason, generation: generation)
        }
    }

    /// Cancel any pending restart operation
    func cancelPendingRestart() {
        isRestarting = false
        currentAttempt = 0
        restartGeneration &+= 1
    }

    /// Start periodic health check with adaptive interval
    func startHealthCheck() {
        scheduleNextHealthCheck()

        #if DEBUG
        print("💓 Health check started (interval: \(currentHealthCheckInterval)s)")
        #endif
    }

    /// Stop periodic health check
    func stopHealthCheck() {
        healthCheckTimer?.invalidate()
        healthCheckTimer = nil
    }

    /// Reset health check interval to minimum (called after issues detected)
    func resetHealthCheckInterval() {
        currentHealthCheckInterval = Constants.HealthCheck.minInterval
        consecutiveSuccessfulChecks = 0

        // Reschedule with new interval if timer is running
        if healthCheckTimer != nil {
            scheduleNextHealthCheck()
            #if DEBUG
            print("💓 Health check interval reset to minimum: \(currentHealthCheckInterval)s")
            #endif
        }
    }

    private func scheduleNextHealthCheck() {
        healthCheckTimer?.invalidate()

        healthCheckTimer = Timer.scheduledTimer(withTimeInterval: currentHealthCheckInterval, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.performHealthCheck()
            }
        }
    }

    func increaseHealthCheckIntervalIfStable() {
        consecutiveSuccessfulChecks += 1

        if consecutiveSuccessfulChecks >= Constants.HealthCheck.successThresholdForIncrease {
            let newInterval = min(
                currentHealthCheckInterval * Constants.HealthCheck.intervalIncreaseMultiplier,
                Constants.HealthCheck.maxInterval
            )

            if newInterval > currentHealthCheckInterval {
                currentHealthCheckInterval = newInterval
                consecutiveSuccessfulChecks = 0

                #if DEBUG
                print("💓 Health check interval increased to: \(currentHealthCheckInterval)s")
                #endif
            }
        }
    }

    /// Mark successful device start
    func markSuccessfulStart(deviceCount: Int) {
        lastSuccessfulStart = Date()
        consecutiveFailures = 0

        #if DEBUG
        print("✅ Marked successful start with \(deviceCount) device(s)")
        #endif
    }

    // MARK: - Private Methods

    private func performRestart(reason: RestartReason, generation: UInt) {
        guard isRestarting, restartGeneration == generation else { return }

        guard let controller = controller else {
            isRestarting = false
            return
        }

        currentAttempt += 1

        #if DEBUG
        print("🔄 Restart attempt \(currentAttempt)/\(retryConfig.maxAttempts) (reason: \(reason.rawValue))")
        #endif

        // Tear down + recreate via the single controlled entry point
        let deviceCount = controller.stopAndRecreateMultitouch()

        if deviceCount > 0 {
            // Success
            isRestarting = false
            markSuccessfulStart(deviceCount: deviceCount)
            onRestartCompleted?(true, deviceCount)

            #if DEBUG
            print("✅ Restart successful - found \(deviceCount) device(s)")
            #endif
        } else {
            // Failed - retry if attempts remaining
            consecutiveFailures += 1

            if currentAttempt < retryConfig.maxAttempts {
                let delay = retryConfig.delay(forAttempt: currentAttempt)

                #if DEBUG
                print("⚠️ No devices found, retrying in \(String(format: "%.1f", delay))s...")
                #endif

                schedule(delay) { [weak self] in
                    guard let self = self,
                          self.isRestarting,
                          self.restartGeneration == generation else { return }
                    self.performRestart(reason: reason, generation: generation)
                }
            } else {
                // All attempts exhausted
                isRestarting = false
                onRestartFailed?(currentAttempt)

                #if DEBUG
                print("❌ Restart failed after \(currentAttempt) attempts")
                #endif
            }
        }
    }

    private func performHealthCheck() {
        guard let controller = controller,
              controller.isAppEnabled else {
            // Still schedule next check even if disabled
            scheduleNextHealthCheck()
            return
        }

        let deviceCount = controller.currentDeviceCount

        if deviceCount == 0 || !controller.areCurrentDevicesValid {
            #if DEBUG
            print("💓 Health check: No devices detected, triggering restart")
            #endif
            resetHealthCheckInterval()
            restart(reason: .healthCheck, afterDelay: Constants.Timing.accessibilityCheckInterval)
        } else {
            #if DEBUG
            print("💓 Health check: OK (\(deviceCount) device(s)) - next check in \(currentHealthCheckInterval)s")
            #endif
            increaseHealthCheckIntervalIfStable()
            scheduleNextHealthCheck()
        }
    }
}
