import XCTest
@testable import Turbotext

@MainActor
final class TranscriptionServiceTests: XCTestCase {

    private let dummyAudioURL = URL(fileURLWithPath: "/tmp/transcription-service-tests-dummy.m4a")

    override func tearDown() {
        KeychainService.delete(key: .groqAPIKey)
        KeychainService.delete(key: .openAIAPIKey)
        resetQuotaStore()
        super.tearDown()
    }

    private func resetQuotaStore() {
        let store = GroqQuotaStore.shared
        store.activateFallback(resetAt: Date().addingTimeInterval(-10))
        store.clearIfExpired()
    }

    func testNormalSuccessUsesGroqAndDoesNotActivateFallback() async throws {
        let router = CloudTranscriptionRouter(
            groqKey: { "gsk_test_key" },
            groqTranscribe: { _, _, _, _ in
                ("Hallo Welt", GroqRateLimitInfo(remainingAudioSeconds: 500, resetAt: nil))
            },
            openAITranscribe: { _, _, _ in
                XCTFail("OpenAI should not be called on Groq success")
                return ""
            }
        )

        let outcome = try await router.transcribe(
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
        let resetAt = Date().addingTimeInterval(3600)
        let router = CloudTranscriptionRouter(
            groqKey: { "gsk_test_key" },
            groqTranscribe: { _, _, _, _ in
                throw GroqTranscriptionError.rateLimitExceeded(resetAt: resetAt)
            },
            openAITranscribe: { _, _, _ in
                "Fallback Text"
            }
        )

        let outcome = try await router.transcribe(
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
        GroqQuotaStore.shared.activateFallback(resetAt: Date().addingTimeInterval(3600))
        let router = CloudTranscriptionRouter(
            groqKey: { "gsk_test_key" },
            groqTranscribe: { _, _, _, _ in
                XCTFail("Groq should not be called while fallback is active")
                return ("", GroqRateLimitInfo(remainingAudioSeconds: nil, resetAt: nil))
            },
            openAITranscribe: { _, _, _ in
                "Direct OpenAI Text"
            }
        )

        let outcome = try await router.transcribe(
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
        let router = CloudTranscriptionRouter(
            groqKey: { "gsk_test_key" },
            groqQuotaCheck: { apiKey in
                XCTAssertEqual(apiKey, "gsk_test_key")
                return GroqRateLimitInfo(remainingAudioSeconds: 321, resetAt: resetAt)
            }
        )

        await router.checkGroqQuotaIfNeeded(secureLocalModeEnabled: false)

        XCTAssertEqual(GroqQuotaStore.shared.remainingAudioSeconds, 321)
        XCTAssertEqual(GroqQuotaStore.shared.rateLimitResetAt, resetAt)
    }

    func testQuotaCheckActivatesFallbackThroughRouter() async {
        let resetAt = Date().addingTimeInterval(3600)
        let router = CloudTranscriptionRouter(
            groqKey: { "gsk_test_key" },
            groqQuotaCheck: { _ in
                throw GroqTranscriptionError.rateLimitExceeded(resetAt: resetAt)
            }
        )

        await router.checkGroqQuotaIfNeeded(secureLocalModeEnabled: false)

        XCTAssertTrue(GroqQuotaStore.shared.fallbackActive)
        XCTAssertEqual(GroqQuotaStore.shared.rateLimitResetAt, resetAt)
    }

    func testQuotaCheckSkipsWhenRouterHasNoGroqKey() async {
        let router = CloudTranscriptionRouter(
            groqKey: { nil },
            groqQuotaCheck: { _ in
                XCTFail("Quota check should not run without a Groq key")
                return GroqRateLimitInfo(remainingAudioSeconds: 321, resetAt: nil)
            }
        )

        await router.checkGroqQuotaIfNeeded(secureLocalModeEnabled: false)

        XCTAssertNil(GroqQuotaStore.shared.remainingAudioSeconds)
        XCTAssertFalse(GroqQuotaStore.shared.fallbackActive)
    }
}
