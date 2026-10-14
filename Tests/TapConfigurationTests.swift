import XCTest

@testable import TapperLib

class TapConfigurationTests: XCTestCase {

    func testDefaultConfigurationMatchesInitializerDefaults() {
        XCTAssertEqual(TapConfiguration.default, TapConfiguration())
    }

    func testDefaultConfigurationUsesExpectedRightClickArea() {
        XCTAssertEqual(TapConfiguration.default.rightClickAreaThreshold, 0.6, accuracy: 0.001)
    }

    func testDefaultRightClickThresholdClearsNormalClickDuration() {
        // 0.1s sat inside the natural 80-150ms duration of a deliberate click,
        // so right-half clicks were misread as right-clicks.
        XCTAssertEqual(TapConfiguration.default.rightClickTimeThreshold, 0.16, accuracy: 0.001)
    }

    func testDefaultScrollIntentThresholds() {
        XCTAssertEqual(TapConfiguration.default.surfacePathThreshold, 0.10, accuracy: 0.001)
        XCTAssertEqual(TapConfiguration.default.scrollVelocityThreshold, 1.0, accuracy: 0.001)
    }

    func testDecodingLegacyConfigurationWithoutNewerKeysKeepsSavedValues() throws {
        // JSON written by a version that predates surfacePathThreshold and
        // scrollVelocityThreshold must still decode, preserving custom values
        // and filling the new keys with their defaults.
        let legacyJSON = """
        {
            "tapTimeThreshold": 0.5,
            "tapMovementThreshold": 12.0,
            "rightClickTimeThreshold": 0.2,
            "doubleTapTimeWindow": 0.25,
            "minTapDuration": 0.05,
            "dragThreshold": 3.0,
            "quickTapThreshold": 0.12,
            "rightClickAreaThreshold": 0.65,
            "surfaceMovementThreshold": 0.06,
            "quickTouchTimeThreshold": 0.12
        }
        """
        let decoded = try JSONDecoder().decode(TapConfiguration.self, from: Data(legacyJSON.utf8))

        XCTAssertEqual(decoded.tapTimeThreshold, 0.5, accuracy: 0.0001)
        XCTAssertEqual(decoded.tapMovementThreshold, 12.0, accuracy: 0.0001)
        XCTAssertEqual(decoded.rightClickTimeThreshold, 0.2, accuracy: 0.0001)
        XCTAssertEqual(decoded.rightClickAreaThreshold, 0.65, accuracy: 0.0001)
        XCTAssertEqual(decoded.surfacePathThreshold, TapConfiguration.default.surfacePathThreshold, accuracy: 0.0001)
        XCTAssertEqual(decoded.scrollVelocityThreshold, TapConfiguration.default.scrollVelocityThreshold, accuracy: 0.0001)
        XCTAssertFalse(decoded.zoomEnabled)
        XCTAssertFalse(decoded.zoomReversed)
        XCTAssertEqual(decoded.zoomSensitivity, 1)
    }

    func testRoundTripPreservesAllValues() throws {
        var config = TapConfiguration.default
        config.surfacePathThreshold = 0.18
        config.scrollVelocityThreshold = 1.7
        config.zoomEnabled = true
        config.zoomReversed = true
        config.zoomSensitivity = 1.6

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(TapConfiguration.self, from: data)

        XCTAssertEqual(decoded, config)
    }

    func testZoomSensitivityIsBoundedWhenLoadingSettings() throws {
        for (input, expected) in [(-10.0, 0.5), (100.0, 2.0)] {
            let data = Data("{\"zoomSensitivity\":\(input)}".utf8)
            XCTAssertEqual(try JSONDecoder().decode(TapConfiguration.self, from: data).zoomSensitivity, expected)
        }
    }
}
