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

@MainActor
struct CloudTranscriptionRouter {
    typealias GroqTranscribe = (URL, String, [String], String?) async throws -> (text: String, rateLimitInfo: GroqRateLimitInfo)
    typealias OpenAITranscribe = (URL, [String], String?) async throws -> String
    typealias GroqQuotaCheck = (String) async throws -> GroqRateLimitInfo
    typealias GroqKeyLoader = () -> String?

    private let groqKey: GroqKeyLoader
    private let groqTranscribe: GroqTranscribe
    private let openAITranscribe: OpenAITranscribe
    private let groqQuotaCheck: GroqQuotaCheck
    private let quotaManager: QuotaManager

    init(
        groqKey: @escaping GroqKeyLoader = { KeychainService.load(key: .groqAPIKey) },
        groqTranscribe: @escaping GroqTranscribe = GroqTranscriptionService.transcribe,
        openAITranscribe: @escaping OpenAITranscribe = OpenAITranscriptionService.transcribe,
        groqQuotaCheck: @escaping GroqQuotaCheck = GroqTranscriptionService.checkQuota,
        quotaManager: QuotaManager = GroqQuotaManager.shared
    ) {
        self.groqKey = groqKey
        self.groqTranscribe = groqTranscribe
        self.openAITranscribe = openAITranscribe
        self.groqQuotaCheck = groqQuotaCheck
        self.quotaManager = quotaManager
    }

    func transcribe(
        audioURL: URL,
        durationSeconds: TimeInterval,
        customTerms: [String] = [],
        language: String? = nil
    ) async throws -> TranscriptionOutcome {
        let fallbackWasActive = quotaManager.fallbackActive

        if let groqKey = groqKey(), !fallbackWasActive {
            do {
                let (text, info) = try await groqTranscribe(audioURL, groqKey, customTerms, language)
                updateQuota(info: info, durationSeconds: durationSeconds)
                return .success(text)
            } catch GroqTranscriptionError.rateLimitExceeded(let resetAt) {
                quotaManager.activateFallback(resetAt: resetAt)
                let text = try await openAITranscribe(audioURL, customTerms, language)
                return .fallbackActivated(text)
            }
        }

        let text = try await openAITranscribe(audioURL, customTerms, language)
        return fallbackWasActive ? .fallbackActivated(text) : .success(text)
    }

    func checkGroqQuotaIfNeeded(secureLocalModeEnabled: Bool) async {
        guard let apiKey = groqKey() else { return }
        let shouldCheck = GroqQuotaCheckScheduler.shouldCheck(
            hasGroqKey: true,
            secureLocalModeEnabled: secureLocalModeEnabled,
            remainingAudioSeconds: quotaManager.remainingAudioSeconds,
            fallbackActive: quotaManager.fallbackActive
        )
        guard shouldCheck else { return }
        await checkGroqQuota(apiKey: apiKey)
    }

    private func checkGroqQuota(apiKey: String) async {
        do {
            let info = try await groqQuotaCheck(apiKey)
            if let remaining = info.remainingAudioSeconds {
                quotaManager.update(remainingSeconds: remaining, resetAt: info.resetAt)
            }
        } catch GroqTranscriptionError.rateLimitExceeded(let resetAt) {
            quotaManager.activateFallback(resetAt: resetAt)
        } catch {
        }
    }

    private func updateQuota(info: GroqRateLimitInfo, durationSeconds: TimeInterval) {
        if let remaining = info.remainingAudioSeconds {
            quotaManager.update(remainingSeconds: remaining, resetAt: info.resetAt)
        }
        quotaManager.recordUsage(seconds: Int(durationSeconds.rounded()))
    }
}
