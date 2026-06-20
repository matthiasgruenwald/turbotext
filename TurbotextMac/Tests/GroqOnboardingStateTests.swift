import XCTest
@testable import Turbotext

final class GroqOnboardingStateTests: XCTestCase {

    func testResolveReturnsMissingWhenNoGroqKey() {
        XCTAssertEqual(GroqOnboardingState.resolve(hasGroqKey: false), .missing)
    }

    func testResolveReturnsConfiguredWhenGroqKeyPresent() {
        XCTAssertEqual(GroqOnboardingState.resolve(hasGroqKey: true), .configured)
    }

    @MainActor
    func testAppStateGroqOnboardingStateReflectsKeychain() {
        KeychainService.delete(key: .groqAPIKey)
        defer { KeychainService.delete(key: .groqAPIKey) }

        let appState = AppState()
        XCTAssertEqual(appState.groqOnboardingState, .missing)

        try? KeychainService.save(key: .groqAPIKey, value: "gsk_test_key_1234567890")
        XCTAssertEqual(appState.groqOnboardingState, .configured)
    }
}
