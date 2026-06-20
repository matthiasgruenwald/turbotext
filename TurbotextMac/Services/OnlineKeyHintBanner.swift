import Foundation

/// Pure decision logic for the main-window hint banner shown when the user is
/// online but hasn't stored an OpenAI or Groq key yet.
enum OnlineKeyHintBanner {
    static func content(secureLocalModeEnabled: Bool, hasAnyAPIKey: Bool) -> (title: String, detail: String)? {
        guard !secureLocalModeEnabled, !hasAnyAPIKey else { return nil }
        return (
            title: "Kein API Key hinterlegt",
            detail: "Trage einen OpenAI Key in den Zugangsdaten ein, um Turbotext online zu nutzen."
        )
    }
}
