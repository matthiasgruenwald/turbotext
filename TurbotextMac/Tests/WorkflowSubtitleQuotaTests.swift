import XCTest
@testable import Turbotext

@MainActor
final class WorkflowSubtitleQuotaTests: XCTestCase {

    override func tearDown() {
        KeychainService.delete(key: .groqAPIKey)
        resetQuotaStore()
        super.tearDown()
    }

    private func resetQuotaStore() {
        let store = GroqQuotaStore.shared
        store.activateFallback(resetAt: Date().addingTimeInterval(-10))
        store.clearIfExpired()
    }

    func testNoGroqKeyReturnsOpenAIWithoutQuotaNote() throws {
        KeychainService.delete(key: .groqAPIKey)
        let appState = AppState()
        XCTAssertEqual(appState.workflowSubtitle(for: .transcription), "Online: OpenAI Whisper.")
    }

    func testGroqActiveWithRemainingKnownShowsRemaining() throws {
        try KeychainService.save(key: .groqAPIKey, value: "gsk_test_key_1234567890")
        GroqQuotaStore.shared.update(remainingSeconds: 300, resetAt: Date().addingTimeInterval(3600))
        let appState = AppState()
        XCTAssertEqual(appState.workflowSubtitle(for: .transcription), "Online: Groq Whisper · noch 5 Min.")
    }

    func testGroqActiveWithRemainingUnknownShowsPlainGroq() throws {
        try KeychainService.save(key: .groqAPIKey, value: "gsk_test_key_1234567890")
        let appState = AppState()
        XCTAssertEqual(appState.workflowSubtitle(for: .transcription), "Online: Groq Whisper.")
    }

    func testFallbackActiveShowsExhaustedNote() throws {
        try KeychainService.save(key: .groqAPIKey, value: "gsk_test_key_1234567890")
        GroqQuotaStore.shared.activateFallback(resetAt: Date().addingTimeInterval(3600))
        let appState = AppState()
        XCTAssertEqual(appState.workflowSubtitle(for: .transcription), "Online: OpenAI Whisper · Groq aufgebraucht.")
    }
}
