import XCTest

@testable import TapperLib

final class MouseSpeedManagerTests: XCTestCase {
    private var defaultsSuiteName: String!
    private var defaults: UserDefaults!
    private var backend: FakeMouseSpeedBackend!

    override func setUp() {
        super.setUp()
        defaultsSuiteName = "MouseSpeedManagerTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuiteName)!
        backend = FakeMouseSpeedBackend()
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        defaultsSuiteName = nil
        defaults = nil
        backend = nil
        super.tearDown()
    }

    func testClampLimitsSpeedRange() {
        XCTAssertEqual(MouseSpeedManager.clamp(-1.0), 0.0)
        XCTAssertEqual(MouseSpeedManager.clamp(3.5), 3.5)
        XCTAssertEqual(MouseSpeedManager.clamp(12.0), 8.0)
    }

    func testPrepareSavesBaselineWithoutChangingSystemWhenNoLastSpeedExists() throws {
        backend.readValue = 1.7
        let manager = MouseSpeedManager(defaults: defaults, backend: backend)

        let current = try manager.prepare()

        XCTAssertEqual(current, 1.7)
        XCTAssertEqual(backend.writtenValues, [])
    }

    func testSetSpeedClampsAndPersistsLastSpeed() throws {
        let manager = MouseSpeedManager(defaults: defaults, backend: backend)

        let applied = try manager.setSpeed(12.0)
        let reloaded = MouseSpeedManager(defaults: defaults, backend: backend)

        XCTAssertEqual(applied, 8.0)
        XCTAssertEqual(manager.currentSpeed, 8.0)
        XCTAssertEqual(reloaded.currentSpeed, 8.0)
        XCTAssertEqual(backend.writtenValues, [8.0])
    }

    func testPrepareAppliesPersistedLastSpeed() throws {
        let manager = MouseSpeedManager(defaults: defaults, backend: backend)
        _ = try manager.setSpeed(4.2)
        backend.writtenValues.removeAll()

        let reloaded = MouseSpeedManager(defaults: defaults, backend: backend)
        let current = try reloaded.prepare()

        XCTAssertEqual(current, 4.2)
        XCTAssertEqual(backend.writtenValues, [4.2])
    }

    func testRestoreDefaultUsesSavedBaselineAndClearsLastSpeed() throws {
        backend.readValue = 1.3
        let manager = MouseSpeedManager(defaults: defaults, backend: backend)
        _ = try manager.prepare()
        _ = try manager.setSpeed(5.0)
        backend.writtenValues.removeAll()

        let restored = try manager.restoreSystemDefault()
        let reloaded = MouseSpeedManager(defaults: defaults, backend: backend)

        XCTAssertEqual(restored, 1.3)
        XCTAssertEqual(reloaded.currentSpeed, 1.3)
        XCTAssertEqual(backend.writtenValues, [1.3])
    }

    func testSetSpeedSurfacesBackendFailure() {
        backend.writeError = MouseSpeedError.writeFailed("boom")
        let manager = MouseSpeedManager(defaults: defaults, backend: backend)

        XCTAssertThrowsError(try manager.setSpeed(2.0)) { error in
            XCTAssertEqual(error as? MouseSpeedError, .writeFailed("boom"))
        }
        XCTAssertEqual(manager.currentSpeed, MouseSpeedManager.fallbackSpeed)
    }
}

private final class FakeMouseSpeedBackend: MouseSpeedBackend {
    var readValue = 1.0
    var readError: Error?
    var writeError: Error?
    var writtenValues: [Double] = []

    func readAcceleration() throws -> Double {
        if let readError = readError {
            throw readError
        }

        return readValue
    }

    func writeAcceleration(_ value: Double) throws {
        if let writeError = writeError {
            throw writeError
        }

        writtenValues.append(value)
    }
}
