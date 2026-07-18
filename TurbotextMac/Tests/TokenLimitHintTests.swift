import XCTest
@testable import Turbotext

final class TokenLimitHintTests: XCTestCase {

    func testTextMentionsSharedTokenLimit() {
        XCTAssertEqual(
            TokenLimitHint.text,
            "Das lokale Modell teilt sein 4096-Token-Limit zwischen System-Prompt, Rohtext und Antwort. Längere Prompts lassen weniger Platz für Diktate."
        )
    }

    func testVisibilityMatchesAppleProviderAvailability() {
        XCTAssertEqual(TokenLimitHint.isVisible, RewriteRouter.resolveAppleProvider() != nil)
    }
}
