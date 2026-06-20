import Foundation

/// Pure decision logic for whether a proactive Groq quota check should run.
/// A real transcription already fills `remainingAudioSeconds`; this only covers
/// the gap before the first transcription after app start / day change.
enum GroqQuotaCheckScheduler {
    static func shouldCheck(
        hasGroqKey: Bool,
        secureLocalModeEnabled: Bool,
        remainingAudioSeconds: Int?,
        fallbackActive: Bool
    ) -> Bool {
        guard hasGroqKey, !secureLocalModeEnabled, !fallbackActive else { return false }
        return remainingAudioSeconds == nil
    }
}
