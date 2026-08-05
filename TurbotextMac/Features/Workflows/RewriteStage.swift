import Foundation

enum RewriteStageOutcome: Equatable {
    case rejected
    case rawInsertion(text: String, completionLabel: String)
    case rewritten(text: String, completionLabel: String?)
}

/// Shared rewrite stage of the record-and-rewrite workflows (ADR 0009): applies the
/// short-input gates to the cleaned transcript, runs the rewrite closure on eligible
/// input, and guards the rewrite result with the optional no-speech sentinel (#180).
@MainActor
struct RewriteStage {
    static let rawInsertionCompletionLabel = "Sehr kurze Eingabe – ohne Nachbearbeitung eingefügt"

    private let noSpeechSentinel: String?
    private let rewrite: @MainActor (String) async throws -> RewriteStepResult

    init(
        noSpeechSentinel: String? = nil,
        rewrite: @escaping @MainActor (String) async throws -> RewriteStepResult
    ) {
        self.noSpeechSentinel = noSpeechSentinel
        self.rewrite = rewrite
    }

    func run(_ rawText: String) async throws -> RewriteStageOutcome {
        let transcript = TranscriptionQualityService.cleanedTranscript(rawText)
        if TranscriptionQualityService.isTooShortToRewrite(transcript) {
            return .rejected
        }
        if TranscriptionQualityService.isShortEnoughForRawInsertion(transcript) {
            return .rawInsertion(text: transcript, completionLabel: Self.rawInsertionCompletionLabel)
        }
        let result = try await rewrite(transcript)
        try Task.checkCancellation()
        let rewritten = TranscriptionQualityService.cleanedTranscript(result.text)
        if let noSpeechSentinel, rewritten == noSpeechSentinel {
            return .rejected
        }
        return .rewritten(text: rewritten, completionLabel: result.completionLabel)
    }
}
