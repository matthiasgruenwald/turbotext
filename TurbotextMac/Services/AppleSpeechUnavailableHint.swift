import Foundation

/// Pure decision logic for the explanatory text shown in `TranscriptionSettingsView`
/// when Apple-Gerätetranskription isn't available (macOS < 26, or required assets
/// aren't installed — see `AppleSpeechAvailability`/`AppleSpeechAvailabilityState`).
enum AppleSpeechUnavailableHint {
    static func text(for status: AppleSpeechAvailabilityStatus) -> String? {
        switch status {
        case .available:
            return nil
        case .unsupportedOS:
            return "Apple-Gerätetranskription erfordert macOS 26 oder neuer."
        case .assetsNotInstalled:
            return "Die deutschen Sprachassets für Apple-Gerätetranskription sind nicht installiert."
        case .assetsDownloading:
            return "Die deutschen Sprachassets für Apple-Gerätetranskription werden noch installiert."
        case .germanAssetsUnsupported:
            return "Deutsche Sprachassets für Apple-Gerätetranskription werden auf diesem Mac nicht unterstützt."
        }
    }

    static func text(isAvailable: Bool) -> String? {
        text(for: isAvailable ? .available : .assetsNotInstalled)
    }
}
