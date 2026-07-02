import Foundation
import Observation

/// Shared lifecycle for the "record -> transcribe -> rewrite" workflows
/// (`TextImprovementWorkflow`, `DampfAblassenWorkflow`, `EmojiTextWorkflow`).
///
/// Implements `start`/`stop`/`reset`, cancellation, error handling, and phase
/// transitions exactly once. Subclasses only supply the rewrite step via
/// `rewrite(_:)` and, optionally, a sentinel value the rewriter returns to signal
/// "no usable speech" instead of throwing.
///
/// `cleanedTranscript()` is applied twice by design: once inside
/// `SpokenWorkflowPipeline.transcribeRecording` on the raw transcript (so the
/// rewriter always receives trimmed input), and once here on the rewriter's
/// output (so trailing/leading whitespace the rewriter introduces doesn't leak
/// into the pasted result). `TranscriptionWorkflow` only needs the first call,
/// since it has no rewrite step.
@Observable
@MainActor
class SpokenRewriteWorkflow: Workflow {
    let type: WorkflowType
    var phase: WorkflowPhase = .idle {
        didSet { onPhaseChange?(phase) }
    }
    var onOutput: WorkflowOutputHandler?
    var onPhaseChange: WorkflowPhaseChangeHandler?

    let pipeline: SpokenWorkflowPipeline
    private let customTerms: [String]
    private let language: String
    private let transcriber: SpokenWorkflowPipeline.Transcriber
    private let rewritingMessage: String
    private let noSpeechSentinel: String?
    private var processingTask: Task<Void, Never>?

    init(
        type: WorkflowType,
        customTerms: [String],
        language: String,
        rewritingMessage: String,
        noSpeechSentinel: String? = nil,
        pipeline: SpokenWorkflowPipeline? = nil,
        transcriber: @escaping SpokenWorkflowPipeline.Transcriber
    ) {
        self.type = type
        self.customTerms = customTerms
        self.language = language
        self.rewritingMessage = rewritingMessage
        self.noSpeechSentinel = noSpeechSentinel
        self.pipeline = pipeline ?? SpokenWorkflowPipeline()
        self.transcriber = transcriber
    }

    /// Override point: turn the raw (already-cleaned) transcript into the final text.
    func rewrite(_ transcript: String) async throws -> String {
        fatalError("subclasses must override rewrite(_:)")
    }

    // MARK: - Recording State

    var isRecording: Bool { pipeline.isRecording }
    var audioLevel: Float { pipeline.audioLevel }

    // MARK: - Workflow Protocol

    func start() {
        switch pipeline.startRecording() {
        case .success:
            phase = .running("Aufnahme läuft ...")
        case .failure(let error):
            phase = .error(error.localizedDescription)
        }
    }

    func stop() {
        if pipeline.isRecording {
            switch pipeline.stopRecording() {
            case .success(let recording):
                processRecording(recording)
            case .failure(let error):
                phase = .error(error.localizedDescription)
            }
        } else {
            processingTask?.cancel()
            processingTask = nil
            phase = .idle
        }
    }

    func reset() {
        processingTask?.cancel()
        processingTask = nil
        pipeline.resetRecording()
        phase = .idle
    }

    // MARK: - Two-Phase Processing: Transcribe -> Rewrite

    private func processRecording(_ recording: SpokenWorkflowPipeline.Recording) {
        phase = .running("Wird transkribiert ...")

        processingTask = Task {
            do {
                let rawText = try await pipeline.transcribeRecording(
                    recording,
                    customTerms: customTerms,
                    language: language,
                    transcriber: transcriber
                )
                try Task.checkCancellation()

                phase = .running(rewritingMessage)
                let result = try await rewrite(rawText)
                try Task.checkCancellation()

                let cleanedResult = TranscriptionQualityService.cleanedTranscript(result)
                if let noSpeechSentinel, cleanedResult == noSpeechSentinel {
                    phase = .error("Keine Aufnahme erkannt.")
                    return
                }
                phase = .done(cleanedResult)
                onOutput?(cleanedResult)
            } catch is CancellationError {
                return
            } catch SpokenWorkflowPipeline.Error.noSpeech {
                phase = .error("Keine Aufnahme erkannt.")
            } catch {
                phase = .error(error.localizedDescription)
            }
        }
    }
}
