import Foundation

/// Thin wrapper around `QuotaManager` (#70) that formats Groq quota/fallback state for UI.
/// `AppState` delegates here; this type does not know about `AppState` directly.
@MainActor
final class QuotaAndFallbackState {
    let quotaManager: QuotaManager

    init(quotaManager: QuotaManager = GroqQuotaManager.shared) {
        self.quotaManager = quotaManager
    }

    var fallbackActive: Bool { quotaManager.fallbackActive }
    var rateLimitResetAt: Date? { quotaManager.rateLimitResetAt }
    var remainingAudioSeconds: Int? { quotaManager.remainingAudioSeconds }
    var formattedUsedToday: String { quotaManager.formattedUsedToday }

    func fallbackBannerContent(secureLocalModeEnabled: Bool) -> (title: String, detail: String)? {
        guard !secureLocalModeEnabled, quotaManager.fallbackActive else { return nil }
        var detail = "OpenAI Whisper aktiv."
        if let resetAt = quotaManager.rateLimitResetAt {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            detail += " Groq zurück um \(formatter.string(from: resetAt))."
        }
        return (title: "Groq-Kontingent aufgebraucht", detail: detail)
    }
}
