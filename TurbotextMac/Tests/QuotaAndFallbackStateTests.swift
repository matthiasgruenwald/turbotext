import XCTest
@testable import Turbotext

@MainActor
final class QuotaAndFallbackStateTests: XCTestCase {

    private func makeQuotaManager() -> GroqQuotaManager {
        GroqQuotaManager(defaults: InMemoryPersistence())
    }

    func testFallbackBannerContentNilWhenFallbackInactive() {
        let state = QuotaAndFallbackState(quotaManager: makeQuotaManager())
        XCTAssertNil(state.fallbackBannerContent(secureLocalModeEnabled: false))
    }

    func testFallbackBannerContentNilWhenSecureLocalModeActive() {
        let quotaManager = makeQuotaManager()
        quotaManager.activateFallback(resetAt: nil)
        let state = QuotaAndFallbackState(quotaManager: quotaManager)
        XCTAssertNil(state.fallbackBannerContent(secureLocalModeEnabled: true))
    }

    func testFallbackBannerContentWithoutResetTimeWhenUnknown() {
        let quotaManager = makeQuotaManager()
        quotaManager.activateFallback(resetAt: nil)
        let state = QuotaAndFallbackState(quotaManager: quotaManager)
        let content = state.fallbackBannerContent(secureLocalModeEnabled: false)
        XCTAssertEqual(content?.title, "Groq-Kontingent aufgebraucht")
        XCTAssertEqual(content?.detail, "OpenAI Whisper aktiv.")
    }

    func testFallbackBannerContentWithFormattedResetTime() {
        var components = DateComponents()
        components.year = 2026
        components.month = 6
        components.day = 20
        components.hour = 14
        components.minute = 30
        let resetAt = Calendar.current.date(from: components)!
        let quotaManager = makeQuotaManager()
        quotaManager.activateFallback(resetAt: resetAt)
        let state = QuotaAndFallbackState(quotaManager: quotaManager)

        let content = state.fallbackBannerContent(secureLocalModeEnabled: false)

        XCTAssertEqual(content?.detail, "OpenAI Whisper aktiv. Groq zurück um 14:30.")
    }

    func testUsesInjectedQuotaManagerNotSharedSingleton() {
        let quotaManager = makeQuotaManager()
        quotaManager.activateFallback(resetAt: nil)
        let state = QuotaAndFallbackState(quotaManager: quotaManager)

        XCTAssertTrue(state.fallbackActive)
        XCTAssertFalse(GroqQuotaManager.shared.fallbackActive)
    }
}
