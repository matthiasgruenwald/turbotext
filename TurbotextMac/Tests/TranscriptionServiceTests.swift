import XCTest
@testable import Turbotext

@MainActor
final class TranscriptionServiceTests: XCTestCase {

    private let dummyAudioURL = URL(fileURLWithPath: "/tmp/transcription-service-tests-dummy.m4a")

    override func tearDown() {
        KeychainService.delete(key: .groqAPIKey)
        KeychainService.delete(key: .openAIAPIKey)
        resetQuotaStore()
        restoreDefaultSeams()
        super.tearDown()
    }

    private func resetQuotaStore() {
        let store = GroqQuotaStore.shared
        store.activateFallback(resetAt: Date().addingTimeInterval(-10))
        store.clearIfExpired()
    }

    private func restoreDefaultSeams() {
        TranscriptionService.groqTranscribe = { audioURL, apiKey, customTerms, language in
            try await GroqTranscriptionService.transcribe(
                audioURL: audioURL,
                apiKey: apiKey,
                customTerms: customTerms,
                language: language
            )
        }
        TranscriptionService.openAITranscribe = { audioURL, customTerms, language in
            throw TranscriptionError.notConfigured
        }
    }

    func testNormalSuccessUsesGroqAndDoesNotActivateFallback() async throws {
        try KeychainService.save(key: .groqAPIKey, value: "gsk_test_key")
        TranscriptionService.groqTranscribe = { _, _, _, _ in
            ("Hallo Welt", GroqRateLimitInfo(remainingAudioSeconds: 500, resetAt: nil))
        }
        TranscriptionService.openAITranscribe = { _, _, _ in
            XCTFail("OpenAI should not be called on Groq success")
            return ""
        }

        let outcome = try await TranscriptionService.transcribe(
            audioURL: dummyAudioURL,
            durationSeconds: 2
        )

        guard case .success(let text) = outcome else {
            return XCTFail("Expected .success, got \(outcome)")
        }
        XCTAssertEqual(text, "Hallo Welt")
        XCTAssertFalse(GroqQuotaStore.shared.fallbackActive)
        XCTAssertEqual(GroqQuotaStore.shared.remainingAudioSeconds, 500)
    }

    func testGroq429ActivatesFallbackAndReturnsOpenAIText() async throws {
        try KeychainService.save(key: .groqAPIKey, value: "gsk_test_key")
        let resetAt = Date().addingTimeInterval(3600)
        TranscriptionService.groqTranscribe = { _, _, _, _ in
            throw GroqTranscriptionError.rateLimitExceeded(resetAt: resetAt)
        }
        TranscriptionService.openAITranscribe = { _, _, _ in
            "Fallback Text"
        }

        let outcome = try await TranscriptionService.transcribe(
            audioURL: dummyAudioURL,
            durationSeconds: 2
        )

        guard case .fallbackActivated(let text) = outcome else {
            return XCTFail("Expected .fallbackActivated, got \(outcome)")
        }
        XCTAssertEqual(text, "Fallback Text")
        XCTAssertTrue(GroqQuotaStore.shared.fallbackActive)
        XCTAssertEqual(GroqQuotaStore.shared.rateLimitResetAt, resetAt)
    }

    func testFallbackAlreadyActiveGoesStraightToOpenAI() async throws {
        try KeychainService.save(key: .groqAPIKey, value: "gsk_test_key")
        GroqQuotaStore.shared.activateFallback(resetAt: Date().addingTimeInterval(3600))
        TranscriptionService.groqTranscribe = { _, _, _, _ in
            XCTFail("Groq should not be called while fallback is active")
            return ("", GroqRateLimitInfo(remainingAudioSeconds: nil, resetAt: nil))
        }
        TranscriptionService.openAITranscribe = { _, _, _ in
            "Direct OpenAI Text"
        }

        let outcome = try await TranscriptionService.transcribe(
            audioURL: dummyAudioURL,
            durationSeconds: 2
        )

        guard case .fallbackActivated(let text) = outcome else {
            return XCTFail("Expected .fallbackActivated, got \(outcome)")
        }
        XCTAssertEqual(text, "Direct OpenAI Text")
    }
}
