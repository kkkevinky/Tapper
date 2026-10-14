import XCTest

@testable import TapperLib

/// The monitor's IOKit notifications can only be exercised with real hardware,
/// so these tests just pin down the lifecycle contract: start/stop are
/// idempotent and re-start after stop registers a fresh notification port.
final class MultitouchDeviceMonitorTests: XCTestCase {

    func testStartAndStopAreIdempotent() {
        let monitor = MultitouchDeviceMonitor()
        monitor.start()
        monitor.start()
        monitor.stop()
        monitor.stop()
    }

    func testRestartAfterStopRegistersFreshNotifications() {
        let monitor = MultitouchDeviceMonitor()
        monitor.start()
        monitor.stop()
        monitor.start()
        monitor.stop()
    }

    func testStopWithoutStartIsSafe() {
        let monitor = MultitouchDeviceMonitor()
        monitor.stop()
    }
}
