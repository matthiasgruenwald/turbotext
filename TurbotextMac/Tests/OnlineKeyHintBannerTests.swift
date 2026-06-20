import XCTest
@testable import Turbotext

final class OnlineKeyHintBannerTests: XCTestCase {

    func testReturnsNilWhenSecureLocalModeActive() {
        XCTAssertNil(OnlineKeyHintBanner.content(secureLocalModeEnabled: true, hasAnyAPIKey: false))
    }

    func testReturnsNilWhenKeyPresent() {
        XCTAssertNil(OnlineKeyHintBanner.content(secureLocalModeEnabled: false, hasAnyAPIKey: true))
    }

    func testReturnsContentWhenOnlineWithoutKey() {
        let content = OnlineKeyHintBanner.content(secureLocalModeEnabled: false, hasAnyAPIKey: false)
        XCTAssertEqual(content?.title, "Kein API Key hinterlegt")
        XCTAssertEqual(content?.detail, "Trage einen OpenAI Key in den Zugangsdaten ein, um Turbotext online zu nutzen.")
    }
}
