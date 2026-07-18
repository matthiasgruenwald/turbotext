import XCTest
@testable import Turbotext

final class RecordingOverlaySettingTests: XCTestCase {

    func testAppSettingsDefaultsRecordingOverlayModeToScreenBottomCenter() {
        XCTAssertEqual(AppSettings().recordingOverlayMode, .screenBottomCenter)
    }

    func testAppSettingsDecodingWithoutRecordingOverlayModeKeyDefaultsToScreenBottomCenter() throws {
        let json = """
        {
            "hotkeyMode": "hold",
            "hasSeenOnboarding": true
        }
        """
        let data = Data(json.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(settings.recordingOverlayMode, .screenBottomCenter)
    }

    func testAppSettingsMigratesTextCursorModeToScreenBottomCenter() throws {
        let json = """
        {
            "recordingOverlayMode": "textCursor"
        }
        """

        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))

        XCTAssertEqual(settings.recordingOverlayMode, .screenBottomCenter)
    }

    func testAppSettingsRoundTripsRecordingOverlayModeOff() throws {
        var settings = AppSettings()
        settings.recordingOverlayMode = .off

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(decoded.recordingOverlayMode, .off)
    }

    func testAppSettingsRoundTripsRecordingOverlayModeScreenBottomCenter() throws {
        var settings = AppSettings()
        settings.recordingOverlayMode = .screenBottomCenter

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(decoded.recordingOverlayMode, .screenBottomCenter)
    }

    func testRecordingOverlayModeOffersTheTwoSupportedPositioningChoices() {
        XCTAssertEqual(Set(RecordingOverlayMode.allCases), [.off, .screenBottomCenter])
    }

    // MARK: - Rewrite completion label (#128)

    func testAppSettingsDefaultsHideRewriteCompletionLabelToFalse() {
        XCTAssertFalse(AppSettings().hideRewriteCompletionLabel)
    }

    func testAppSettingsDecodingWithoutHideRewriteCompletionLabelKeyDefaultsToFalse() throws {
        let json = """
        {
            "hotkeyMode": "hold"
        }
        """
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        XCTAssertFalse(settings.hideRewriteCompletionLabel)
    }

    func testAppSettingsRoundTripsHideRewriteCompletionLabel() throws {
        var settings = AppSettings()
        settings.hideRewriteCompletionLabel = true

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertTrue(decoded.hideRewriteCompletionLabel)
    }
}
