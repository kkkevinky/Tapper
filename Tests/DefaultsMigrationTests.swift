import XCTest

@testable import TapperLib

final class DefaultsMigrationTests: XCTestCase {
    private var suiteName: String!
    private var legacyName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "DefaultsMigrationTests-\(UUID().uuidString)"
        legacyName = suiteName + ".legacy"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults.removePersistentDomain(forName: legacyName)
        suiteName = nil
        legacyName = nil
        defaults = nil
        super.tearDown()
    }

    func testLegacyDomainKeepsBuildSuffix() {
        XCTAssertEqual(DefaultsMigration.legacyDomain(for: "io.github.kkkevinky.tapper"), "com.magictapper.app")
        XCTAssertEqual(DefaultsMigration.legacyDomain(for: "io.github.kkkevinky.tapper.debug"), "com.magictapper.app.debug")
        XCTAssertNil(DefaultsMigration.legacyDomain(for: "com.example.other"))
        XCTAssertNil(DefaultsMigration.legacyDomain(for: nil))
    }

    func testCopiesLegacySettingsUnderNewPrefix() {
        defaults.setPersistentDomain([
            "com.magictapper.tune.swipeResendEnd": true,
            "com.magictapper.pointerSpeed.last": 0.89,
            "preventSleepEnabled": true,
        ], forName: legacyName)

        DefaultsMigration.run(defaults: defaults, legacyDomain: legacyName)

        XCTAssertEqual(defaults.object(forKey: "io.github.kkkevinky.tapper.tune.swipeResendEnd") as? Bool, true)
        XCTAssertEqual(defaults.double(forKey: "io.github.kkkevinky.tapper.pointerSpeed.last"), 0.89, accuracy: 0.0001)
        XCTAssertEqual(defaults.object(forKey: "preventSleepEnabled") as? Bool, true)
        XCTAssertNil(defaults.object(forKey: "com.magictapper.tune.swipeResendEnd"))
        XCTAssertTrue(defaults.bool(forKey: DefaultsMigration.doneKey))
    }

    func testKeepsNewerValuesAndRunsOnce() {
        defaults.set(0.5, forKey: "io.github.kkkevinky.tapper.pointerSpeed.last")
        defaults.setPersistentDomain(["com.magictapper.pointerSpeed.last": 0.89], forName: legacyName)

        DefaultsMigration.run(defaults: defaults, legacyDomain: legacyName)
        XCTAssertEqual(defaults.double(forKey: "io.github.kkkevinky.tapper.pointerSpeed.last"), 0.5, accuracy: 0.0001)

        defaults.setPersistentDomain(["com.magictapper.tune.restAge": 0.7], forName: legacyName)
        DefaultsMigration.run(defaults: defaults, legacyDomain: legacyName)
        XCTAssertNil(defaults.object(forKey: "io.github.kkkevinky.tapper.tune.restAge"))
    }

    func testMissingLegacyDomainStillMarksDone() {
        DefaultsMigration.run(defaults: defaults, legacyDomain: legacyName)
        XCTAssertTrue(defaults.bool(forKey: DefaultsMigration.doneKey))
    }
}
