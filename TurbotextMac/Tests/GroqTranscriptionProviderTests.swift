import XCTest
import Observation
@testable import Turbotext

@MainActor
@Observable
private final class FakeQuotaManager: QuotaManager {
    private(set) var remainingAudioSeconds: Int?
    private(set) var recordedUsageSeconds: [Int] = []
    private(set) var updateCallCount = 0

    var formattedUsedToday: String { "0 Sek." }

    func recordUsage(seconds: Int) {
        recordedUsageSeconds.append(seconds)
    }

    func update(remainingSeconds: Int) {
        updateCallCount += 1
        remainingAudioSeconds = remainingSeconds
    }
}

@MainActor
final class GroqTranscriptionProviderTests: XCTestCase {

    private let dummyAudioURL = URL(fileURLWithPath: "/tmp/groq-transcription-provider-tests-dummy.m4a")

    func testGroq429ActivatesFallbackOnInjectedFallbackManager() async throws {
        let fakeQuotaManager = FakeQuotaManager()
        let fallbackManager = GroqFallbackManager(defaults: InMemoryPersistence())
        let resetAt = Date().addingTimeInterval(3600)
        let provider = GroqTranscriptionProvider(
            groqKey: { "gsk_test_key" },
            groqTranscribe: { _, _, _, _ in
                throw GroqTranscriptionError.rateLimitExceeded(resetAt: resetAt)
            },
            openAITranscribe: { _, _, _ in "Fallback Text" },
            quotaManager: fakeQuotaManager,
            fallbackManager: fallbackManager
        )

        let outcome = try await provider.transcribe(audioURL: dummyAudioURL, durationSeconds: 2)

        guard case .fallbackActivated(let text) = outcome else {
            return XCTFail("Expected .fallbackActivated, got \(outcome)")
        }
        XCTAssertEqual(text, "Fallback Text")
        XCTAssertTrue(provider.quotaUIStatus.fallbackActive)
        XCTAssertEqual(provider.quotaUIStatus.rateLimitResetAt, resetAt)
    }

    func testSuccessUpdatesQuotaOnInjectedQuotaManager() async throws {
        let fakeQuotaManager = FakeQuotaManager()
        let fallbackManager = GroqFallbackManager(defaults: InMemoryPersistence())
        let provider = GroqTranscriptionProvider(
            groqKey: { "gsk_test_key" },
            groqTranscribe: { _, _, _, _ in
                ("Hallo Welt", GroqRateLimitInfo(remainingAudioSeconds: 500, resetAt: nil))
            },
            openAITranscribe: { _, _, _ in
                XCTFail("OpenAI should not be called on Groq success")
                return ""
            },
            quotaManager: fakeQuotaManager,
            fallbackManager: fallbackManager
        )

        let outcome = try await provider.transcribe(audioURL: dummyAudioURL, durationSeconds: 2)

        guard case .success(let text) = outcome else {
            return XCTFail("Expected .success, got \(outcome)")
        }
        XCTAssertEqual(text, "Hallo Welt")
        XCTAssertEqual(fakeQuotaManager.updateCallCount, 1)
        XCTAssertEqual(fakeQuotaManager.remainingAudioSeconds, 500)
        XCTAssertEqual(fakeQuotaManager.recordedUsageSeconds, [2])
        XCTAssertFalse(provider.quotaUIStatus.fallbackActive)
    }

    func testQuotaUIStatusReflectsFallbackAndFormattedUsage() async throws {
        let fakeQuotaManager = FakeQuotaManager()
        let fallbackManager = GroqFallbackManager(defaults: InMemoryPersistence())
        let resetAt = Date().addingTimeInterval(1800)
        let provider = GroqTranscriptionProvider(
            groqKey: { "gsk_test_key" },
            groqTranscribe: { _, _, _, _ in
                throw GroqTranscriptionError.rateLimitExceeded(resetAt: resetAt)
            },
            openAITranscribe: { _, _, _ in "Fallback Text" },
            quotaManager: fakeQuotaManager,
            fallbackManager: fallbackManager
        )

        _ = try await provider.transcribe(audioURL: dummyAudioURL, durationSeconds: 2)

        let status = provider.quotaUIStatus
        XCTAssertTrue(status.fallbackActive)
        XCTAssertEqual(status.rateLimitResetAt, resetAt)
        XCTAssertEqual(status.formattedUsedToday, "0 Sek.")
    }

    func testOnFallbackStateChangedProxiesFallbackManagerCallback() {
        let fallbackManager = GroqFallbackManager(defaults: InMemoryPersistence())
        let provider = GroqTranscriptionProvider(
            quotaManager: FakeQuotaManager(),
            fallbackManager: fallbackManager
        )
        var receivedStates: [Bool] = []
        provider.onFallbackStateChanged = { receivedStates.append($0) }

        fallbackManager.reportRateLimitExceeded(resetAt: Date().addingTimeInterval(3600))

        XCTAssertEqual(receivedStates, [true])
    }
}
