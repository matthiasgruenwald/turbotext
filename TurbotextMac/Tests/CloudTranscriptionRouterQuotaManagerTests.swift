import XCTest
import Observation
@testable import Turbotext

@MainActor
@Observable
private final class FakeQuotaManager: QuotaManager {
    private(set) var rateLimitResetAt: Date?
    private(set) var remainingAudioSeconds: Int?
    private(set) var recordedUsageSeconds: [Int] = []
    private(set) var updateCallCount = 0

    var formattedUsedToday: String { "0 Sek." }

    func recordUsage(seconds: Int) {
        recordedUsageSeconds.append(seconds)
    }

    func update(remainingSeconds: Int, resetAt: Date?) {
        updateCallCount += 1
        remainingAudioSeconds = remainingSeconds
        if let resetAt {
            rateLimitResetAt = resetAt
        }
    }
}

@MainActor
final class CloudTranscriptionRouterQuotaManagerTests: XCTestCase {

    private let dummyAudioURL = URL(fileURLWithPath: "/tmp/cloud-transcription-router-quota-manager-tests-dummy.m4a")

    func testGroq429ActivatesFallbackOnInjectedFallbackManager() async throws {
        let fakeQuotaManager = FakeQuotaManager()
        let fallbackManager = GroqFallbackManager(defaults: InMemoryPersistence())
        let resetAt = Date().addingTimeInterval(3600)
        let router = CloudTranscriptionRouter(
            groqKey: { "gsk_test_key" },
            groqTranscribe: { _, _, _, _ in
                throw GroqTranscriptionError.rateLimitExceeded(resetAt: resetAt)
            },
            openAITranscribe: { _, _, _ in "Fallback Text" },
            quotaManager: fakeQuotaManager,
            fallbackManager: fallbackManager
        )

        let outcome = try await router.transcribe(audioURL: dummyAudioURL, durationSeconds: 2)

        guard case .fallbackActivated(let text) = outcome else {
            return XCTFail("Expected .fallbackActivated, got \(outcome)")
        }
        XCTAssertEqual(text, "Fallback Text")
        XCTAssertTrue(fallbackManager.isActive)
        XCTAssertEqual(fallbackManager.rateLimitResetAt, resetAt)
    }

    func testSuccessUpdatesQuotaOnInjectedQuotaManager() async throws {
        let fakeQuotaManager = FakeQuotaManager()
        let fallbackManager = GroqFallbackManager(defaults: InMemoryPersistence())
        let router = CloudTranscriptionRouter(
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

        let outcome = try await router.transcribe(audioURL: dummyAudioURL, durationSeconds: 2)

        guard case .success(let text) = outcome else {
            return XCTFail("Expected .success, got \(outcome)")
        }
        XCTAssertEqual(text, "Hallo Welt")
        XCTAssertEqual(fakeQuotaManager.updateCallCount, 1)
        XCTAssertEqual(fakeQuotaManager.remainingAudioSeconds, 500)
        XCTAssertEqual(fakeQuotaManager.recordedUsageSeconds, [2])
        XCTAssertFalse(fallbackManager.isActive)
    }
}
