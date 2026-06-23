import AppKit

// MARK: - Sound Kind

enum OfflineWarningSoundKind: Equatable {
    case networkUnavailable  // #42: Warnsound, kein Fallback
    // case localFallbackActive wird in #43 ergänzt: informativer Fallback-Sound

    var soundName: String {
        switch self {
        case .networkUnavailable: return "Basso"
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

// MARK: - Player

struct OfflineWarningSoundPlayer {
    static func play(_ kind: OfflineWarningSoundKind = .networkUnavailable) {
        NSSound(named: kind.soundName)?.play()
    }
}
