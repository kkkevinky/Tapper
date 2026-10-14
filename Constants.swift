import Foundation

/// Application-wide constants to avoid magic numbers
enum Constants {

    // MARK: - Timing Constants

    enum Timing {
        /// Interval between accessibility permission checks (seconds)
        static let accessibilityCheckInterval: TimeInterval = 1.0

        /// Maximum time to wait for accessibility permission (seconds)
        static let accessibilityTimeout: TimeInterval = 60.0

        /// Delay after screen unlock before checking devices (seconds)
        static let screenUnlockCheckDelay: TimeInterval = 1.0

        /// Delay before initial restart when no devices found (seconds)
        static let initialRestartDelay: TimeInterval = 2.0
    }

    // MARK: - Health Check Configuration

    enum HealthCheck {
        /// Minimum health check interval (when recovering from issues)
        static let minInterval: TimeInterval = 30.0

        /// Default health check interval (normal operation)
        static let defaultInterval: TimeInterval = 60.0

        /// Maximum health check interval (stable operation)
        static let maxInterval: TimeInterval = 300.0

        /// Number of consecutive successful checks to increase interval
        static let successThresholdForIncrease: Int = 5

        /// Multiplier for increasing interval after stable period
        static let intervalIncreaseMultiplier: Double = 1.5
    }

    // MARK: - Sleep/Wake Recovery

    enum SleepRecovery {
        /// Threshold for "long sleep" detection (seconds) - 1 hour
        static let longSleepThreshold: TimeInterval = 3600.0

        /// Threshold for "medium sleep" detection (seconds) - 5 minutes
        static let mediumSleepThreshold: TimeInterval = 300.0

        /// Initial delay after long sleep (> 1 hour)
        static let longSleepDelay: TimeInterval = 5.0

        /// Initial delay after medium sleep (5 min - 1 hour)
        static let mediumSleepDelay: TimeInterval = 3.0

        /// Initial delay after short sleep (< 5 minutes)
        static let shortSleepDelay: TimeInterval = 2.0

        /// Delay before restart triggered by Bluetooth reconnect
        static let bluetoothReconnectDelay: TimeInterval = 1.0
    }

    // MARK: - Retry Configuration

    enum Retry {
        /// Maximum number of restart attempts
        static let maxAttempts: Int = 10

        /// Initial delay between retry attempts (seconds)
        static let initialDelay: TimeInterval = 2.0

        /// Maximum delay between retry attempts (seconds)
        static let maxDelay: TimeInterval = 30.0

        /// Multiplier for exponential backoff
        static let backoffMultiplier: Double = 1.5
    }

    // MARK: - Sleep Prevention

    enum SleepPrevention {
        /// Reason reported to the system for the power assertion
        static let assertionReason = "Tapper is actively processing Magic Mouse tap events"

        /// UserDefaults key for the prevent-sleep toggle
        static let userDefaultsKey = "preventSleepEnabled"
    }

    // MARK: - System Notifications

    enum Notifications {
        /// Screen unlock notification name
        static let screenUnlocked = "com.apple.screenIsUnlocked"
    }

    // MARK: - URLs

    enum URLs {
        /// System Settings Accessibility pane URL
        static let accessibilitySettings = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    }

    // MARK: - App Info

    enum App {
        static let name = "Tapper"
        static var version: String {
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
                ?? "Development"
        }
    }
}
