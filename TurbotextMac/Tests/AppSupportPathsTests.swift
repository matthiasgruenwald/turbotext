import XCTest
@testable import Turbotext

final class AppSupportPathsTests: XCTestCase {

    func testAppSupportDirectoryIsIsolatedFromProductionUnderTests() {
        XCTAssertFalse(AppSupportPaths.appSupportDirectoryURL.path.hasSuffix("/Turbotext"))
        XCTAssertTrue(AppSupportPaths.appSupportDirectoryURL.path.hasSuffix("/TurbotextTests"))
    }

    func testSettingsURLLivesUnderIsolatedDirectory() {
        XCTAssertEqual(
            AppSupportPaths.settingsURL,
            AppSupportPaths.appSupportDirectoryURL.appendingPathComponent("settings.json")
        )
    }
}
