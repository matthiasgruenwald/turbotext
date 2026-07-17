import Foundation

/// Pure decision logic for the main-window hint banner shown when the user is
/// online but hasn't stored an OpenAI or Groq key yet.
enum OnlineKeyHintBanner {
    static func content(alwaysLocalTranscription: Bool, hasAnyAPIKey: Bool) -> (title: String, detail: String)? {
        guard !alwaysLocalTranscription, !hasAnyAPIKey else { return nil }
        return (
            title: "Kein API Key hinterlegt",
            detail: "Trage einen OpenAI Key in den Zugangsdaten ein, um Turbotext online zu nutzen."
        )
    }
}
