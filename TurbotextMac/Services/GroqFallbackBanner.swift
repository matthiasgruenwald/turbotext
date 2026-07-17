import Foundation

/// Pure decision logic for the Groq-fallback banner shown when quota is exhausted
/// and Turbotext has fallen back to OpenAI Whisper.
enum GroqFallbackBanner {
    static func content(
        fallbackActive: Bool,
        resetAt: Date?,
        alwaysLocalTranscription: Bool
    ) -> (title: String, detail: String)? {
        guard !alwaysLocalTranscription, fallbackActive else { return nil }
        var detail = "OpenAI Whisper aktiv."
        if let resetAt {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            detail += " Groq zurück um \(formatter.string(from: resetAt))."
        }
        return (title: "Groq-Kontingent aufgebraucht", detail: detail)
    }
}
