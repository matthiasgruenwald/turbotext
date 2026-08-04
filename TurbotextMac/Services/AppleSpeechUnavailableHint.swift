import Foundation

/// Pure decision logic for the explanatory text shown when Apple-Gerätetranskription
/// isn't available — in `TranscriptionSettingsView` and as the live-session refusal
/// (Sprachasset-Sicherstellung, #178). Missing assets are never reported as a dead end:
/// Turbotext installs them itself, so the text asks for a retry while they load.
enum AppleSpeechUnavailableHint {
    static let assetsLoadingMessage = "Sprachassets werden geladen – bitte gleich erneut versuchen."

    static func text(for status: AppleSpeechAvailabilityStatus) -> String? {
        switch status {
        case .available:
            return nil
        case .unsupportedOS:
            return "Apple-Gerätetranskription erfordert macOS 26 oder neuer."
        case .assetsNotInstalled, .assetsDownloading:
            return assetsLoadingMessage
        case .germanAssetsUnsupported:
            return "Deutsche Sprachassets für Apple-Gerätetranskription werden auf diesem Mac nicht unterstützt."
        }
    }

    static func text(isAvailable: Bool) -> String? {
        text(for: isAvailable ? .available : .assetsNotInstalled)
    }

    static func refusalText(for status: AppleSpeechAvailabilityStatus) -> String {
        text(for: status) ?? "Apple-Gerätetranskription ist derzeit nicht verfügbar."
    }
}
