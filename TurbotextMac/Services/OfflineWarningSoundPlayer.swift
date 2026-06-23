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

// MARK: - Decision Logic

enum OfflineWarningSoundDecision {
    private static let cloudWorkflowTypes: Set<WorkflowType> = [
        .transcription, .textImprover, .dampfAblassen, .emojiText
    ]

    static func kind(
        for status: NetworkQualityStatus,
        workflowType: WorkflowType
    ) -> OfflineWarningSoundKind? {
        guard status == .red, cloudWorkflowTypes.contains(workflowType) else { return nil }
        return .networkUnavailable
    }
}

// MARK: - Transcription Backend Fallback Decision (#43)

struct TranscriptionFallbackDecision: Equatable {
    let backend: TranscriptionBackend
    let soundKind: OfflineWarningSoundKind?
}

enum TranscriptionFallbackResolver {
    /// Decides which backend to use for a transcription hotkey press and which sound to play,
    /// based on network status, the auto-fallback toggle, and whether the local model is installed.
    /// Only `.transcription` is eligible for local fallback — other cloud workflow types
    /// (`textImprover`, `dampfAblassen`, `emojiText`) keep the #42 warning-sound-only behavior.
    static func resolve(
        for status: NetworkQualityStatus,
        workflowType: WorkflowType,
        autoFallbackToLocalOnOffline: Bool,
        isLocalModelInstalled: Bool
    ) -> TranscriptionFallbackDecision {
        guard status == .red, workflowType == .transcription else {
            return TranscriptionFallbackDecision(
                backend: .remote,
                soundKind: OfflineWarningSoundDecision.kind(for: status, workflowType: workflowType)
            )
        }

        guard autoFallbackToLocalOnOffline, isLocalModelInstalled else {
            return TranscriptionFallbackDecision(backend: .remote, soundKind: .networkUnavailable)
        }

        return TranscriptionFallbackDecision(backend: .local, soundKind: .localFallbackActive)
    }
}

// MARK: - Player

struct OfflineWarningSoundPlayer {
    static func play(_ kind: OfflineWarningSoundKind = .networkUnavailable) {
        NSSound(named: kind.soundName)?.play()
    }
}
