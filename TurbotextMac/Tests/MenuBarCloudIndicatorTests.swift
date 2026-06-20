import XCTest
@testable import Turbotext

final class MenuBarCloudIndicatorTests: XCTestCase {

    func testNoneWhileLocalModeEnabled() {
        let result = MenuBarCloudIndicator.resolve(secureLocalModeEnabled: true, hasGroqKey: true, fallbackActive: false)
        XCTAssertEqual(result, .none)
    }

    func testGroqReadyWhenKeyPresentAndNotFallenBack() {
        let result = MenuBarCloudIndicator.resolve(secureLocalModeEnabled: false, hasGroqKey: true, fallbackActive: false)
        XCTAssertEqual(result, .groqReady)
    }

    func testOpenAIFallbackWhenNoGroqKey() {
        let result = MenuBarCloudIndicator.resolve(secureLocalModeEnabled: false, hasGroqKey: false, fallbackActive: false)
        XCTAssertEqual(result, .openAIFallback)
    }

    func testOpenAIFallbackWhenGroqQuotaExhausted() {
        let result = MenuBarCloudIndicator.resolve(secureLocalModeEnabled: false, hasGroqKey: true, fallbackActive: true)
        XCTAssertEqual(result, .openAIFallback)
    }
}
