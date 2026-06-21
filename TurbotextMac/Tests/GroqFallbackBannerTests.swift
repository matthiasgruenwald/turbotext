import XCTest
@testable import Turbotext

@MainActor
final class GroqFallbackBannerTests: XCTestCase {

    override func tearDown() {
        resetQuotaStore()
        super.tearDown()
    }

    private func resetQuotaStore() {
        let store = GroqQuotaStore.shared
        store.activateFallback(resetAt: Date().addingTimeInterval(-10))
        store.clearIfExpired()
    }

    func testReturnsNilWhenFallbackInactive() {
        let appState = AppState()
        XCTAssertNil(appState.groqFallbackBannerContent)
    }

    func testReturnsNilWhenSecureLocalModeActive() {
        GroqQuotaStore.shared.activateFallback(resetAt: nil)
        let appState = AppState()
        appState.appSettings.secureLocalModeEnabled = true
        defer { appState.appSettings.secureLocalModeEnabled = false }
        XCTAssertNil(appState.groqFallbackBannerContent)
    }

    func testReturnsContentWithoutResetTimeWhenUnknown() {
        GroqQuotaStore.shared.activateFallback(resetAt: nil)
        let appState = AppState()
        let content = appState.groqFallbackBannerContent
        XCTAssertEqual(content?.title, "Groq-Kontingent aufgebraucht")
        XCTAssertEqual(content?.detail, "OpenAI Whisper aktiv.")
    }

    func testReturnsContentWithFormattedResetTime() {
        var components = DateComponents()
        components.year = 2026
        components.month = 6
        components.day = 20
        components.hour = 14
        components.minute = 30
        let resetAt = Calendar.current.date(from: components)!
        GroqQuotaStore.shared.activateFallback(resetAt: resetAt)

        let appState = AppState()
        let content = appState.groqFallbackBannerContent
        XCTAssertEqual(content?.title, "Groq-Kontingent aufgebraucht")
        XCTAssertEqual(content?.detail, "OpenAI Whisper aktiv. Groq zurück um 14:30.")
    }
}
