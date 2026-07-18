import Foundation

/// Pure decision logic for the explanatory text shown in `TranscriptionSettingsView`
/// when Apple-Gerätetranskription isn't available (macOS < 26, or required assets
/// aren't installed — see `AppleSpeechAvailability`/`AppleSpeechAvailabilityState`).
enum AppleSpeechUnavailableHint {
    static func text(isAvailable: Bool) -> String? {
        guard !isAvailable else { return nil }
        return "Apple-Gerätetranskription erfordert macOS 26 oder neuer sowie installierte Spracherkennungs-Assets. Bis dahin steht nur WhisperKit (Legacy) zur Verfügung."
    }
}
