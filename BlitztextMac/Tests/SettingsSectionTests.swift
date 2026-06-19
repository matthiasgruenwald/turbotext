import XCTest
@testable import Blitztext

final class SettingsSectionTests: XCTestCase {

    func testDefaultSectionIsCredentialsWhenAccessibilityNotGranted() {
        XCTAssertEqual(
            SettingsSection.defaultSection(accessibilityPermissionGranted: false),
            .credentials
        )
    }

    func testDefaultSectionIsTranscriptionWhenAccessibilityGranted() {
        XCTAssertEqual(
            SettingsSection.defaultSection(accessibilityPermissionGranted: true),
            .transcription
        )
    }

    func testAllCasesOrderedAsSpecified() {
        XCTAssertEqual(
            SettingsSection.allCases,
            [.transcription, .workflows, .shortcuts, .credentials, .appManagement]
        )
    }
}
