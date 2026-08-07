import AppKit

// MARK: - Sound Kind

enum OfflineWarningSoundKind: Equatable {
    case networkUnavailable  // #42: Warnsound, kein Fallback
    case localFallbackActive // #43: informativer Sound, Fallback läuft lokal weiter

    var soundName: String {
        switch self {
        case .networkUnavailable: return "Basso"
        case .localFallbackActive: return "Pop"
        }
    }
}

// MARK: - Player

/// Purely mechanical: plays whatever `OfflineWarningSoundKind` it's handed. Which kind (or
/// none) belongs to a given hotkey press is decided exactly once, by
/// `TranscriptionBackendResolver` (#193) — this type has no opinion on that.
struct OfflineWarningSoundPlayer {
    static func play(_ kind: OfflineWarningSoundKind = .networkUnavailable) {
        NSSound(named: kind.soundName)?.play()
    }
}
