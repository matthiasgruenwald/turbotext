import XCTest
@testable import Turbotext

final class GroqFallbackBannerTests: XCTestCase {

    func testContentNilWhenFallbackInactive() {
        XCTAssertNil(GroqFallbackBanner.content(fallbackActive: false, resetAt: nil, secureLocalModeEnabled: false))
    }

    func testContentNilWhenSecureLocalModeActive() {
        XCTAssertNil(GroqFallbackBanner.content(fallbackActive: true, resetAt: nil, secureLocalModeEnabled: true))
    }

    func testContentWithoutResetTimeWhenUnknown() {
        let content = GroqFallbackBanner.content(fallbackActive: true, resetAt: nil, secureLocalModeEnabled: false)
        XCTAssertEqual(content?.title, "Groq-Kontingent aufgebraucht")
        XCTAssertEqual(content?.detail, "OpenAI Whisper aktiv.")
    }

    func testContentWithFormattedResetTime() {
        var components = DateComponents()
        components.year = 2026
        components.month = 6
        components.day = 20
        components.hour = 14
        components.minute = 30
        let resetAt = Calendar.current.date(from: components)!

        let content = GroqFallbackBanner.content(fallbackActive: true, resetAt: resetAt, secureLocalModeEnabled: false)

        XCTAssertEqual(content?.title, "Groq-Kontingent aufgebraucht")
        XCTAssertEqual(content?.detail, "OpenAI Whisper aktiv. Groq zurück um 14:30.")
    }
}

@MainActor
final class GroqFallbackBannerAppStateIntegrationTests: XCTestCase {

    override func tearDown() {
        resetQuotaStore()
        super.tearDown()
    }

    private func resetQuotaStore() {
        let store = GroqQuotaManager.shared
        store.activateFallback(resetAt: Date().addingTimeInterval(-10))
        store.checkIfExpired()
    }

    func testAppStateReturnsNilWhenFallbackInactive() {
        let appState = AppState()
        XCTAssertNil(appState.groqFallbackBannerContent)
    }

    func testAppStateReturnsNilWhenSecureLocalModeActive() {
        GroqQuotaManager.shared.activateFallback(resetAt: nil)
        let appState = AppState()
        appState.appSettings.secureLocalModeEnabled = true
        defer { appState.appSettings.secureLocalModeEnabled = false }
        XCTAssertNil(appState.groqFallbackBannerContent)
    }

    func testAppStateReturnsContentWhenFallbackActive() {
        GroqQuotaManager.shared.activateFallback(resetAt: nil)
        let appState = AppState()
        let content = appState.groqFallbackBannerContent
        XCTAssertEqual(content?.title, "Groq-Kontingent aufgebraucht")
        XCTAssertEqual(content?.detail, "OpenAI Whisper aktiv.")
    }
}
