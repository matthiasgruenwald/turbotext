import XCTest
@testable import Turbotext

final class DockModeSettingTests: XCTestCase {

    func testAppSettingsDefaultsDockModeEnabledToTrue() {
        XCTAssertTrue(AppSettings().dockModeEnabled)
    }

    func testAppSettingsDecodingWithoutDockModeKeyDefaultsToTrue() throws {
        let json = """
        {
            "hotkeyMode": "hold",
            "hasSeenOnboarding": true
        }
        """
        let data = Data(json.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertTrue(settings.dockModeEnabled)
    }

    func testAppSettingsRoundTripsDockModeDisabled() throws {
        var settings = AppSettings()
        settings.dockModeEnabled = false

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertFalse(decoded.dockModeEnabled)
    }

    func testAppSettingsRoundTripsDockModeEnabled() throws {
        var settings = AppSettings()
        settings.dockModeEnabled = true

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertTrue(decoded.dockModeEnabled)
    }
}
