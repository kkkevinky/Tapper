import XCTest

@testable import TapperLib

@MainActor
final class MultitouchRestartManagerTests: XCTestCase {

    // MARK: - RetryConfig.delay(forAttempt:)

    func testRetryDelayGrowsExponentiallyAndCapsAtMaxDelay() {
        let config = MultitouchRestartManager.RetryConfig(
            maxAttempts: 10,
            initialDelay: 2.0,
            maxDelay: 30.0,
            backoffMultiplier: 2.0
        )

        XCTAssertEqual(config.delay(forAttempt: 1), 2.0, accuracy: 0.001)   // 2 * 2^0
        XCTAssertEqual(config.delay(forAttempt: 2), 4.0, accuracy: 0.001)   // 2 * 2^1
        XCTAssertEqual(config.delay(forAttempt: 3), 8.0, accuracy: 0.001)   // 2 * 2^2
        XCTAssertEqual(config.delay(forAttempt: 4), 16.0, accuracy: 0.001)  // 2 * 2^3
        XCTAssertEqual(config.delay(forAttempt: 5), 30.0, accuracy: 0.001)  // 2 * 2^4 = 32 -> capped to 30
        XCTAssertEqual(config.delay(forAttempt: 100), 30.0, accuracy: 0.001) // stays capped
    }

    func testDefaultRetryConfigMatchesConstants() {
        let config = MultitouchRestartManager.RetryConfig.default
        XCTAssertEqual(config.maxAttempts, Constants.Retry.maxAttempts)
        XCTAssertEqual(config.initialDelay, Constants.Retry.initialDelay)
        XCTAssertEqual(config.maxDelay, Constants.Retry.maxDelay)
        XCTAssertEqual(config.backoffMultiplier, Constants.Retry.backoffMultiplier)
    }

    // MARK: - Restart loop (synchronous scheduler)

    func testRestartFailsAfterMaxAttemptsWhenControllerAlwaysReturnsZero() {
        let controller = FakeController(deviceCounts: [0, 0, 0, 0, 0], isEnabled: true)
        let manager = MultitouchRestartManager(
            controller: controller,
            config: .init(maxAttempts: 5, initialDelay: 0, maxDelay: 1, backoffMultiplier: 1),
            schedule: SyncScheduler.run
        )

        var failedAttempts: Int?
        manager.onRestartFailed = { attempts in failedAttempts = attempts }
        var completed: (Bool, Int)?
        manager.onRestartCompleted = { ok, count in completed = (ok, count) }

        manager.restart(reason: .manual)

        XCTAssertEqual(controller.recreateCallCount, 5, "Should attempt once per maxAttempts")
        XCTAssertEqual(failedAttempts, 5)
        XCTAssertNil(completed, "Should not report success when all attempts fail")
        XCTAssertEqual(manager.consecutiveFailures, 5)
        XCTAssertNil(manager.lastSuccessfulStart)
    }

    func testRestartSucceedsOnRetryWhenControllerRecoverOnSecondAttempt() {
        // First recreate returns 0 (failure), second returns 2 (success)
        let controller = FakeController(deviceCounts: [0, 2], isEnabled: true)
        let manager = MultitouchRestartManager(
            controller: controller,
            config: .init(maxAttempts: 5, initialDelay: 0, maxDelay: 1, backoffMultiplier: 1),
            schedule: SyncScheduler.run
        )

        var completed: (Bool, Int)?
        manager.onRestartCompleted = { ok, count in completed = (ok, count) }
        var failedAttempts: Int?
        manager.onRestartFailed = { attempts in failedAttempts = attempts }

        manager.restart(reason: .systemWake)

        XCTAssertEqual(controller.recreateCallCount, 2)
        XCTAssertEqual(completed?.0, true)
        XCTAssertEqual(completed?.1, 2)
        XCTAssertNil(failedAttempts)
        XCTAssertEqual(manager.consecutiveFailures, 0, "Successful start resets the failure counter")
        XCTAssertNotNil(manager.lastSuccessfulStart)
    }

    func testRestartSucceedsImmediatelyWhenDevicesPresent() {
        let controller = FakeController(deviceCounts: [3], isEnabled: true)
        let manager = MultitouchRestartManager(
            controller: controller,
            config: .init(maxAttempts: 5, initialDelay: 0, maxDelay: 1, backoffMultiplier: 1),
            schedule: SyncScheduler.run
        )

        var completed: (Bool, Int)?
        manager.onRestartCompleted = { ok, count in completed = (ok, count) }

        manager.restart(reason: .manual)

        XCTAssertEqual(controller.recreateCallCount, 1)
        XCTAssertEqual(completed?.0, true)
        XCTAssertEqual(completed?.1, 3)
        XCTAssertEqual(manager.consecutiveFailures, 0)
    }

    func testRestartWithInitialDelaySchedulesWorkThenRuns() {
        let controller = FakeController(deviceCounts: [1], isEnabled: true)
        var scheduledDelays: [TimeInterval] = []
        let manager = MultitouchRestartManager(
            controller: controller,
            config: .init(maxAttempts: 3, initialDelay: 0, maxDelay: 1, backoffMultiplier: 1),
            schedule: { delay, work in
                scheduledDelays.append(delay)
                work()
            }
        )

        manager.restart(reason: .systemWake, afterDelay: 2.5)

        XCTAssertEqual(scheduledDelays.first, 2.5, "Initial delay should be passed to scheduler")
        XCTAssertEqual(controller.recreateCallCount, 1)
    }

    // MARK: - Cancellation

    func testCancelPendingRestartStopsTheRetryLoop() {
        // Controller never succeeds; with an async scheduler the work is pending.
        let controller = FakeController(deviceCounts: [0, 0, 0, 0, 0], isEnabled: true)
        var scheduledWork: [() -> Void] = []
        let manager = MultitouchRestartManager(
            controller: controller,
            config: .init(maxAttempts: 5, initialDelay: 0, maxDelay: 1, backoffMultiplier: 1),
            schedule: { _, work in scheduledWork.append(work) }
        )

        var failedAttempts: Int?
        manager.onRestartFailed = { attempts in failedAttempts = attempts }

        // kick off: first attempt runs synchronously (delay 0 -> performRestart called directly),
        // then a retry is scheduled (captured, not run).
        manager.restart(reason: .manual)
        XCTAssertEqual(controller.recreateCallCount, 1)
        XCTAssertEqual(scheduledWork.count, 1)

        manager.cancelPendingRestart()

        // Drain scheduled work; it should be a no-op because isRestarting was cleared.
        scheduledWork.forEach { $0() }

        XCTAssertEqual(controller.recreateCallCount, 1, "No further attempts after cancel")
        XCTAssertNil(failedAttempts, "onRestartFailed should not fire after cancel")
    }

    func testCancelPendingRestartStopsInitialDelayedAttempt() {
        let controller = FakeController(deviceCounts: [1], isEnabled: true)
        var scheduledWork: [() -> Void] = []
        let manager = MultitouchRestartManager(
            controller: controller,
            config: .init(maxAttempts: 3, initialDelay: 1, maxDelay: 1, backoffMultiplier: 1),
            schedule: { _, work in scheduledWork.append(work) }
        )

        manager.restart(reason: .systemWake, afterDelay: 2)
        XCTAssertEqual(scheduledWork.count, 1)

        manager.cancelPendingRestart()
        scheduledWork.forEach { $0() }

        XCTAssertEqual(
            controller.recreateCallCount,
            0,
            "Cancelling must invalidate the initial delayed attempt as well as retries"
        )
    }

    func testOlderDelayedRestartCannotJoinNewRestartSequence() {
        let controller = FakeController(deviceCounts: [1, 1], isEnabled: true)
        var scheduledWork: [() -> Void] = []
        let manager = MultitouchRestartManager(
            controller: controller,
            config: .init(maxAttempts: 3, initialDelay: 1, maxDelay: 1, backoffMultiplier: 1),
            schedule: { _, work in scheduledWork.append(work) }
        )

        manager.restart(reason: .systemWake, afterDelay: 2)
        manager.restart(reason: .bluetoothReconnect)
        XCTAssertEqual(controller.recreateCallCount, 1)

        scheduledWork.forEach { $0() }
        XCTAssertEqual(
            controller.recreateCallCount,
            1,
            "A delayed task from an older generation must not run inside the new sequence"
        )
    }

    // MARK: - Successful start bookkeeping

    func testMarkSuccessfulStartResetsConsecutiveFailuresAndRecordsDate() {
        let controller = FakeController(deviceCounts: [], isEnabled: true)
        let manager = MultitouchRestartManager(
            controller: controller,
            config: .default,
            schedule: SyncScheduler.run
        )

        // Simulate prior failures by running a failing restart sequence.
        manager.restart(reason: .manual)  // default config: 10 attempts, all fail
        XCTAssertEqual(manager.consecutiveFailures, 10)

        manager.markSuccessfulStart(deviceCount: 2)

        XCTAssertEqual(manager.consecutiveFailures, 0)
        XCTAssertNotNil(manager.lastSuccessfulStart)
    }

    // MARK: - Health check interval progression

    func testIncreaseHealthCheckIntervalReachesMaxAfterEnoughStableChecks() {
        let manager = MultitouchRestartManager(
            controller: FakeController(deviceCounts: [], isEnabled: true),
            config: .default,
            schedule: SyncScheduler.run
        )

        // Start at min so each step is deterministic.
        manager.resetHealthCheckInterval()
        let minInterval = Constants.HealthCheck.minInterval
        XCTAssertEqual(manager.currentHealthCheckInterval, minInterval)

        // successThresholdForIncrease stable checks should bump the interval once.
        let threshold = Constants.HealthCheck.successThresholdForIncrease
        for _ in 0..<threshold {
            manager.increaseHealthCheckIntervalIfStable()
        }
        let expected = min(minInterval * Constants.HealthCheck.intervalIncreaseMultiplier,
                           Constants.HealthCheck.maxInterval)
        XCTAssertEqual(manager.currentHealthCheckInterval, expected, accuracy: 0.001)
        XCTAssertEqual(manager.consecutiveSuccessfulChecks, 0, "Counter should reset after an increase")

        // Keep bumping until we hit the cap.
        var iterations = 0
        while manager.currentHealthCheckInterval < Constants.HealthCheck.maxInterval && iterations < 100 {
            for _ in 0..<threshold {
                manager.increaseHealthCheckIntervalIfStable()
            }
            iterations += 1
        }
        XCTAssertEqual(manager.currentHealthCheckInterval, Constants.HealthCheck.maxInterval, accuracy: 0.001)
    }

    func testResetHealthCheckIntervalClearsCounterAndSetsMin() {
        let manager = MultitouchRestartManager(
            controller: FakeController(deviceCounts: [], isEnabled: true),
            config: .default,
            schedule: SyncScheduler.run
        )

        // Bump interval up a bit first.
        let threshold = Constants.HealthCheck.successThresholdForIncrease
        for _ in 0..<threshold {
            manager.increaseHealthCheckIntervalIfStable()
        }
        XCTAssertGreaterThan(manager.currentHealthCheckInterval, Constants.HealthCheck.minInterval)

        manager.resetHealthCheckInterval()

        XCTAssertEqual(manager.currentHealthCheckInterval, Constants.HealthCheck.minInterval)
        XCTAssertEqual(manager.consecutiveSuccessfulChecks, 0)
    }
}

// MARK: - Fakes

private final class FakeController: MultitouchController {
    var scriptedDeviceCounts: [Int]
    var isAppEnabled: Bool
    private(set) var recreateCallCount = 0

    init(deviceCounts: [Int], isEnabled: Bool) {
        self.scriptedDeviceCounts = deviceCounts
        self.isAppEnabled = isEnabled
    }

    var currentDeviceCount: Int {
        // Not used by the restart-loop tests; return 0.
        0
    }

    @discardableResult
    func stopAndRecreateMultitouch() -> Int {
        let index = recreateCallCount
        recreateCallCount += 1
        // Return scripted value, or 0 if the script runs out.
        return index < scriptedDeviceCounts.count ? scriptedDeviceCounts[index] : 0
    }
}

private enum SyncScheduler {
    /// Runs the work immediately, ignoring the delay.
    static func run(delay: TimeInterval, work: @escaping () -> Void) {
        work()
    }
}
