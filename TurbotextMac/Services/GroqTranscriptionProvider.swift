import Foundation

enum TranscriptionError: LocalizedError {
    case noFile
    case notConfigured
    case networkError(String)
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .noFile:
            return "Keine Audio-Datei gefunden"
        case .notConfigured:
            return "API Key fehlt. Bitte in den Einstellungen hinterlegen."
        case .networkError(let msg):
            return "Netzwerkfehler: \(msg)"
        case .apiError(let msg):
            return "API-Fehler: \(msg)"
        }
    }
}

enum TranscriptionOutcome {
    case success(String)
    case fallbackActivated(String)

    var text: String {
        switch self {
        case .success(let text), .fallbackActivated(let text):
            return text
        }
    }
}

/// What views need to render Groq quota/fallback UI — a single read-only snapshot
/// instead of reaching into `GroqQuotaManager`/`GroqFallbackManager` directly.
struct GroqQuotaUIStatus: Equatable {
    let formattedUsedToday: String
    let fallbackActive: Bool
    let rateLimitResetAt: Date?
}

/// Encapsulates the Groq-first/OpenAI-fallback routing decision together with the
/// quota tracking (`GroqQuotaManager`) and persistent fallback state machine
/// (`GroqFallbackManager`, ADR-0001) it depends on. Callers get one object and one
/// status surface (`quotaUIStatus`) instead of wiring three collaborators together.
@MainActor
final class GroqTranscriptionProvider {
    typealias GroqTranscribe = (URL, String, [String], String?) async throws -> (text: String, rateLimitInfo: GroqRateLimitInfo)
    typealias OpenAITranscribe = (URL, [String], String?) async throws -> String
    typealias GroqQuotaCheck = (String) async throws -> GroqRateLimitInfo
    typealias GroqKeyLoader = () -> String?

    private let groqKey: GroqKeyLoader
    private let groqTranscribe: GroqTranscribe
    private let openAITranscribe: OpenAITranscribe
    private let groqQuotaCheck: GroqQuotaCheck
    private let quotaManager: QuotaManager
    private let fallbackManager: GroqFallbackManager

    /// Fired whenever the fallback state changes, so observers (e.g. the menu bar icon)
    /// can refresh without polling `quotaUIStatus`.
    var onFallbackStateChanged: ((Bool) -> Void)? {
        get { fallbackManager.onStateChanged }
        set { fallbackManager.onStateChanged = newValue }
    }

    init(
        groqKey: @escaping GroqKeyLoader = { KeychainService.load(key: .groqAPIKey) },
        groqTranscribe: @escaping GroqTranscribe = GroqTranscriptionService.transcribe,
        openAITranscribe: @escaping OpenAITranscribe = OpenAITranscriptionService.transcribe,
        groqQuotaCheck: @escaping GroqQuotaCheck = GroqTranscriptionService.checkQuota,
        quotaManager: QuotaManager = GroqQuotaManager.shared,
        fallbackManager: GroqFallbackManager = GroqFallbackManager.shared
    ) {
        self.groqKey = groqKey
        self.groqTranscribe = groqTranscribe
        self.openAITranscribe = openAITranscribe
        self.groqQuotaCheck = groqQuotaCheck
        self.quotaManager = quotaManager
        self.fallbackManager = fallbackManager
    }

    var quotaUIStatus: GroqQuotaUIStatus {
        GroqQuotaUIStatus(
            formattedUsedToday: quotaManager.formattedUsedToday,
            fallbackActive: fallbackManager.isActive,
            rateLimitResetAt: fallbackManager.rateLimitResetAt
        )
    }

    func transcribe(
        audioURL: URL,
        durationSeconds: TimeInterval,
        customTerms: [String] = [],
        language: String? = nil
    ) async throws -> TranscriptionOutcome {
        let fallbackWasActive = fallbackManager.isActive

        if let groqKey = groqKey(), !fallbackWasActive {
            do {
                let (text, info) = try await groqTranscribe(audioURL, groqKey, customTerms, language)
                updateQuota(info: info, durationSeconds: durationSeconds)
                return .success(text)
            } catch GroqTranscriptionError.rateLimitExceeded(let resetAt) {
                fallbackManager.reportRateLimitExceeded(resetAt: resetAt)
                let text = try await openAITranscribe(audioURL, customTerms, language)
                return .fallbackActivated(text)
            }
        }

        let text = try await openAITranscribe(audioURL, customTerms, language)
        return fallbackWasActive ? .fallbackActivated(text) : .success(text)
    }

    func checkGroqQuotaIfNeeded(alwaysLocalTranscription: Bool) async {
        guard let apiKey = groqKey() else { return }
        let shouldCheck = GroqQuotaCheckScheduler.shouldCheck(
            hasGroqKey: true,
            alwaysLocalTranscription: alwaysLocalTranscription,
            remainingAudioSeconds: quotaManager.remainingAudioSeconds,
            fallbackActive: fallbackManager.isActive
        )
        guard shouldCheck else { return }
        await checkGroqQuota(apiKey: apiKey)
    }

    private func checkGroqQuota(apiKey: String) async {
        do {
            let info = try await groqQuotaCheck(apiKey)
            if let remaining = info.remainingAudioSeconds {
                quotaManager.update(remainingSeconds: remaining)
            }
        } catch GroqTranscriptionError.rateLimitExceeded(let resetAt) {
            fallbackManager.reportRateLimitExceeded(resetAt: resetAt)
        } catch {
        }
    }

    private func updateQuota(info: GroqRateLimitInfo, durationSeconds: TimeInterval) {
        if let remaining = info.remainingAudioSeconds {
            quotaManager.update(remainingSeconds: remaining)
        }
        quotaManager.recordUsage(seconds: Int(durationSeconds.rounded()))
    }
}
