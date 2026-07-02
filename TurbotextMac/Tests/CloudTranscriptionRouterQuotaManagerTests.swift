import XCTest
@testable import Turbotext

@MainActor
private final class FakeQuotaManager: QuotaManager {
    private(set) var fallbackActive = false
    private(set) var rateLimitResetAt: Date?
    private(set) var remainingAudioSeconds: Int?
    private(set) var recordedUsageSeconds: [Int] = []
    private(set) var activateFallbackCallCount = 0
    private(set) var updateCallCount = 0

    var formattedUsedToday: String { "0 Sek." }

    func recordUsage(seconds: Int) {
        recordedUsageSeconds.append(seconds)
    }

    func activateFallback(resetAt: Date?) {
        activateFallbackCallCount += 1
        fallbackActive = true
        rateLimitResetAt = resetAt
        remainingAudioSeconds = 0
    }

    func update(remainingSeconds: Int, resetAt: Date?) {
        updateCallCount += 1
        remainingAudioSeconds = remainingSeconds
        if let resetAt {
            rateLimitResetAt = resetAt
        }
    }

    func checkIfExpired() {}
}

@MainActor
final class CloudTranscriptionRouterQuotaManagerTests: XCTestCase {

    private let dummyAudioURL = URL(fileURLWithPath: "/tmp/cloud-transcription-router-quota-manager-tests-dummy.m4a")

    func testGroq429ActivatesFallbackOnInjectedQuotaManager() async throws {
        let fakeQuotaManager = FakeQuotaManager()
        let resetAt = Date().addingTimeInterval(3600)
        let router = CloudTranscriptionRouter(
            groqKey: { "gsk_test_key" },
            groqTranscribe: { _, _, _, _ in
                throw GroqTranscriptionError.rateLimitExceeded(resetAt: resetAt)
            },
            openAITranscribe: { _, _, _ in "Fallback Text" },
            quotaManager: fakeQuotaManager
        )

        let outcome = try await router.transcribe(audioURL: dummyAudioURL, durationSeconds: 2)

        guard case .fallbackActivated(let text) = outcome else {
            return XCTFail("Expected .fallbackActivated, got \(outcome)")
        }
        XCTAssertEqual(text, "Fallback Text")
        XCTAssertEqual(fakeQuotaManager.activateFallbackCallCount, 1)
        XCTAssertTrue(fakeQuotaManager.fallbackActive)
        XCTAssertEqual(fakeQuotaManager.rateLimitResetAt, resetAt)
    }

    func testSuccessUpdatesQuotaOnInjectedQuotaManager() async throws {
        let fakeQuotaManager = FakeQuotaManager()
        let router = CloudTranscriptionRouter(
            groqKey: { "gsk_test_key" },
            groqTranscribe: { _, _, _, _ in
                ("Hallo Welt", GroqRateLimitInfo(remainingAudioSeconds: 500, resetAt: nil))
            },
            openAITranscribe: { _, _, _ in
                XCTFail("OpenAI should not be called on Groq success")
                return ""
            },
            quotaManager: fakeQuotaManager
        )

        let outcome = try await router.transcribe(audioURL: dummyAudioURL, durationSeconds: 2)

        guard case .success(let text) = outcome else {
            return XCTFail("Expected .success, got \(outcome)")
        }
        XCTAssertEqual(text, "Hallo Welt")
        XCTAssertEqual(fakeQuotaManager.updateCallCount, 1)
        XCTAssertEqual(fakeQuotaManager.remainingAudioSeconds, 500)
        XCTAssertEqual(fakeQuotaManager.recordedUsageSeconds, [2])
        XCTAssertFalse(fakeQuotaManager.fallbackActive)
    }
}
