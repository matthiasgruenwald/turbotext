import XCTest
@testable import Turbotext

final class RecordingOverlaySettingTests: XCTestCase {

    func testAppSettingsDefaultsRecordingOverlayModeToTextCursor() {
        XCTAssertEqual(AppSettings().recordingOverlayMode, .textCursor)
    }

    func testAppSettingsDecodingWithoutRecordingOverlayModeKeyDefaultsToTextCursor() throws {
        let json = """
        {
            "hotkeyMode": "hold",
            "hasSeenOnboarding": true
        }
        """
        let data = Data(json.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(settings.recordingOverlayMode, .textCursor)
    }

    func testAppSettingsRoundTripsRecordingOverlayModeOff() throws {
        var settings = AppSettings()
        settings.recordingOverlayMode = .off

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(decoded.recordingOverlayMode, .off)
    }
}
