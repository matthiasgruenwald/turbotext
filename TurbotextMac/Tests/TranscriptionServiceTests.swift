import XCTest
@testable import Turbotext

@MainActor
final class TranscriptionServiceTests: XCTestCase {

    private let dummyAudioURL = URL(fileURLWithPath: "/tmp/transcription-service-tests-dummy.m4a")

    override func tearDown() {
        KeychainService.delete(key: .groqAPIKey)
        KeychainService.delete(key: .openAIAPIKey)
        resetFallbackStore()
        GroqQuotaManager.shared.resetRemainingAudioSeconds()
        super.tearDown()
    }

    private func resetFallbackStore() {
        let store = GroqFallbackManager.shared
        store.reportRateLimitExceeded(resetAt: Date().addingTimeInterval(-10))
        store.checkIfExpired()
    }

    func testNormalSuccessUsesGroqAndDoesNotActivateFallback() async throws {
        let provider = GroqTranscriptionProvider(
            groqKey: { "gsk_test_key" },
            groqTranscribe: { _, _, _, _ in
                ("Hallo Welt", GroqRateLimitInfo(remainingAudioSeconds: 500, resetAt: nil))
            },
            openAITranscribe: { _, _, _ in
                XCTFail("OpenAI should not be called on Groq success")
                return ""
            }
        )

        let outcome = try await provider.transcribe(
            audioURL: dummyAudioURL,
            durationSeconds: 2
        )

        guard case .success(let text) = outcome else {
            return XCTFail("Expected .success, got \(outcome)")
        }
        XCTAssertEqual(text, "Hallo Welt")
        XCTAssertFalse(GroqFallbackManager.shared.isActive)
        XCTAssertEqual(GroqQuotaManager.shared.remainingAudioSeconds, 500)
    }

    func testGroq429ActivatesFallbackAndReturnsOpenAIText() async throws {
        let resetAt = Date().addingTimeInterval(3600)
        let provider = GroqTranscriptionProvider(
            groqKey: { "gsk_test_key" },
            groqTranscribe: { _, _, _, _ in
                throw GroqTranscriptionError.rateLimitExceeded(resetAt: resetAt)
            },
            openAITranscribe: { _, _, _ in
                "Fallback Text"
            }
        )

        let outcome = try await provider.transcribe(
            audioURL: dummyAudioURL,
            durationSeconds: 2
        )

        guard case .fallbackActivated(let text) = outcome else {
            return XCTFail("Expected .fallbackActivated, got \(outcome)")
        }
        XCTAssertEqual(text, "Fallback Text")
        XCTAssertTrue(GroqFallbackManager.shared.isActive)
        XCTAssertEqual(GroqFallbackManager.shared.rateLimitResetAt, resetAt)
    }

    func testFallbackAlreadyActiveGoesStraightToOpenAI() async throws {
        GroqFallbackManager.shared.reportRateLimitExceeded(resetAt: Date().addingTimeInterval(3600))
        let provider = GroqTranscriptionProvider(
            groqKey: { "gsk_test_key" },
            groqTranscribe: { _, _, _, _ in
                XCTFail("Groq should not be called while fallback is active")
                return ("", GroqRateLimitInfo(remainingAudioSeconds: nil, resetAt: nil))
            },
            openAITranscribe: { _, _, _ in
                "Direct OpenAI Text"
            }
        )

        let outcome = try await provider.transcribe(
            audioURL: dummyAudioURL,
            durationSeconds: 2
        )

        guard case .fallbackActivated(let text) = outcome else {
            return XCTFail("Expected .fallbackActivated, got \(outcome)")
        }
        XCTAssertEqual(text, "Direct OpenAI Text")
    }

    func testQuotaCheckUpdatesQuotaThroughRouter() async {
        let resetAt = Date().addingTimeInterval(3600)
        let provider = GroqTranscriptionProvider(
            groqKey: { "gsk_test_key" },
            groqQuotaCheck: { apiKey in
                XCTAssertEqual(apiKey, "gsk_test_key")
                return GroqRateLimitInfo(remainingAudioSeconds: 321, resetAt: resetAt)
            }
        )

        await provider.checkGroqQuotaIfNeeded(alwaysLocalTranscription: false)

        XCTAssertEqual(GroqQuotaManager.shared.remainingAudioSeconds, 321)
    }

    func testQuotaCheckActivatesFallbackThroughRouter() async {
        let resetAt = Date().addingTimeInterval(3600)
        let provider = GroqTranscriptionProvider(
            groqKey: { "gsk_test_key" },
            groqQuotaCheck: { _ in
                throw GroqTranscriptionError.rateLimitExceeded(resetAt: resetAt)
            }
        )

        await provider.checkGroqQuotaIfNeeded(alwaysLocalTranscription: false)

        XCTAssertTrue(GroqFallbackManager.shared.isActive)
        XCTAssertEqual(GroqFallbackManager.shared.rateLimitResetAt, resetAt)
    }

    func testQuotaCheckSkipsWhenRouterHasNoGroqKey() async {
        let provider = GroqTranscriptionProvider(
            groqKey: { nil },
            groqQuotaCheck: { _ in
                XCTFail("Quota check should not run without a Groq key")
                return GroqRateLimitInfo(remainingAudioSeconds: 321, resetAt: nil)
            }
        )

        await provider.checkGroqQuotaIfNeeded(alwaysLocalTranscription: false)

        XCTAssertNil(GroqQuotaManager.shared.remainingAudioSeconds)
        XCTAssertFalse(GroqFallbackManager.shared.isActive)
    }
}
