import XCTest
@testable import Turbotext

final class GroqFallbackBannerTests: XCTestCase {

    func testContentNilWhenFallbackInactive() {
        XCTAssertNil(GroqFallbackBanner.content(fallbackActive: false, resetAt: nil, alwaysLocalTranscription: false))
    }

    func testContentNilWhenSecureLocalModeActive() {
        XCTAssertNil(GroqFallbackBanner.content(fallbackActive: true, resetAt: nil, alwaysLocalTranscription: true))
    }

    func testContentWithoutResetTimeWhenUnknown() {
        let content = GroqFallbackBanner.content(fallbackActive: true, resetAt: nil, alwaysLocalTranscription: false)
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

        let content = GroqFallbackBanner.content(fallbackActive: true, resetAt: resetAt, alwaysLocalTranscription: false)

        XCTAssertEqual(content?.title, "Groq-Kontingent aufgebraucht")
        XCTAssertEqual(content?.detail, "OpenAI Whisper aktiv. Groq zurück um 14:30.")
    }
}

@MainActor
final class GroqFallbackBannerAppStateIntegrationTests: XCTestCase {

    override func tearDown() {
        resetFallbackStore()
        super.tearDown()
    }

    private func resetFallbackStore() {
        let store = GroqFallbackManager.shared
        store.reportRateLimitExceeded(resetAt: Date().addingTimeInterval(-10))
        store.checkIfExpired()
    }

    func testAppStateReturnsNilWhenFallbackInactive() {
        let appState = AppState()
        XCTAssertNil(appState.groqFallbackBannerContent)
    }

    func testAppStateReturnsNilWhenSecureLocalModeActive() {
        GroqFallbackManager.shared.reportRateLimitExceeded(resetAt: nil)
        let appState = AppState()
        appState.appSettings.alwaysLocalTranscription = true
        defer { appState.appSettings.alwaysLocalTranscription = false }
        XCTAssertNil(appState.groqFallbackBannerContent)
    }

    func testAppStateReturnsContentWhenFallbackActive() {
        GroqFallbackManager.shared.reportRateLimitExceeded(resetAt: nil)
        let appState = AppState()
        let content = appState.groqFallbackBannerContent
        XCTAssertEqual(content?.title, "Groq-Kontingent aufgebraucht")
        XCTAssertEqual(content?.detail, "OpenAI Whisper aktiv.")
    }
}
