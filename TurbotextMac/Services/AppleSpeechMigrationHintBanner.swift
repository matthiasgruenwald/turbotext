import Foundation

/// Pure decision logic for the one-time main-window hint banner that tells users with an
/// installed WhisperKit model about the new Apple on-device transcription backend
/// (Wayfinder #98/#123, issue #126).
enum AppleSpeechMigrationHintBanner {
    static func content(
        isMacOS26OrLater: Bool,
        whisperKitModelInstalled: Bool,
        appleSpeechAvailable: Bool,
        hasSeenHint: Bool
    ) -> (title: String, detail: String)? {
        guard isMacOS26OrLater, whisperKitModelInstalled, appleSpeechAvailable, !hasSeenHint else { return nil }
        return (
            title: "Apple-Gerätetranskription ist jetzt verfügbar.",
            detail: "WhisperKit bleibt als Legacy-Option erhalten."
        )
    }
}
