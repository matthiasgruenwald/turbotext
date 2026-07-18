import XCTest
@testable import Turbotext

@MainActor
final class RewriteConsentResetTests: XCTestCase {

    func testHasRewriteConsentFalseWhenNoneStored() {
        let appState = AppState()
        XCTAssertFalse(appState.hasRewriteConsent(for: .textImprover))
    }

    func testHasRewriteConsentTrueWhenStored() {
        let appState = AppState()
        appState.appSettings.rewriteConsents[.dampfAblassen] = .groq
        XCTAssertTrue(appState.hasRewriteConsent(for: .dampfAblassen))
    }

    func testResetRewriteConsentClearsOnlyTargetWorkflow() {
        let appState = AppState()
        appState.appSettings.rewriteConsents = [.textImprover: .groq, .dampfAblassen: .openAI]

        appState.resetRewriteConsent(for: .textImprover)

        XCTAssertFalse(appState.hasRewriteConsent(for: .textImprover))
        XCTAssertTrue(appState.hasRewriteConsent(for: .dampfAblassen))
    }
}
