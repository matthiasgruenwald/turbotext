import Foundation
import Observation

/// Shared lifecycle for the "record -> transcribe -> rewrite" workflows
/// (Turbotext+, DampfAblassen, EmojiText — see the factory methods below).
///
/// Implements `start`/`stop`/`reset`, cancellation, error handling, and phase
/// transitions exactly once. Callers supply the rewrite step via the `rewrite`
/// closure and, optionally, a sentinel value the rewriter returns to signal
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
final class SpokenRewriteWorkflow: Workflow {
    let type: WorkflowType
    var phase: WorkflowPhase = .idle {
        didSet { onPhaseChange?(phase) }
    }
    var onOutput: WorkflowOutputHandler?
    var onPhaseChange: WorkflowPhaseChangeHandler?
    /// See `Workflow.processingLabel` (#128) — resolved once rewrite processing begins.
    private(set) var processingLabel: String?
    /// See `Workflow.completionLabel` (#128) — set once the rewrite step completes.
    private(set) var completionLabel: String?

    let pipeline: SpokenWorkflowPipeline
    private let customTerms: [String]
    private let language: String
    private let transcriber: SpokenWorkflowPipeline.Transcriber
    private let rewritingMessage: String
    private let noSpeechSentinel: String?
    private let rewrite: (String) async throws -> RewriteStepResult
    private let processingLabelResolver: () -> String?
    private var processingTask: Task<Void, Never>?

    init(
        type: WorkflowType,
        customTerms: [String],
        language: String,
        rewritingMessage: String,
        noSpeechSentinel: String? = nil,
        pipeline: SpokenWorkflowPipeline? = nil,
        transcriber: @escaping SpokenWorkflowPipeline.Transcriber,
        processingLabelResolver: @escaping () -> String? = { nil },
        rewrite: @escaping (String) async throws -> RewriteStepResult
    ) {
        self.type = type
        self.customTerms = customTerms
        self.language = language
        self.rewritingMessage = rewritingMessage
        self.noSpeechSentinel = noSpeechSentinel
        self.pipeline = pipeline ?? SpokenWorkflowPipeline()
        self.transcriber = transcriber
        self.processingLabelResolver = processingLabelResolver
        self.rewrite = rewrite
    }

    // MARK: - Recording State

    var isRecording: Bool { pipeline.isRecording }
    var audioLevel: Float { pipeline.audioLevel }

    // MARK: - Workflow Protocol

    func start() {
        processingLabel = nil
        completionLabel = nil
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
        processingLabel = nil
        completionLabel = nil
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

                // Resolved before flipping `phase`: the `didSet` fires `onPhaseChange`
                // synchronously and `WorkflowOrchestrator` reads `processingLabel` from
                // within that same callback, so it must already hold the new value.
                processingLabel = processingLabelResolver()
                phase = .running(rewritingMessage)
                let result = try await rewrite(rawText)
                try Task.checkCancellation()

                let cleanedResult = TranscriptionQualityService.cleanedTranscript(result.text)
                if let noSpeechSentinel, cleanedResult == noSpeechSentinel {
                    phase = .error("Keine Aufnahme erkannt.")
                    return
                }
                completionLabel = result.completionLabel
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

// MARK: - Factory Methods

extension SpokenRewriteWorkflow {
    typealias Improver = (String, TextImprovementSettings, RewriteProviderMode) async throws -> RewriteStepResult
    typealias DampfAblassenRewriter = (String, DampfAblassenSettings, RewriteProviderMode) async throws -> RewriteStepResult
    typealias EmojiTextRewriter = (String, EmojiTextSettings, RewriteProviderMode) async throws -> RewriteStepResult

    static func textImprovement(
        settings: TextImprovementSettings,
        language: String = "de",
        providerMode: RewriteProviderMode = .auto,
        pipeline: SpokenWorkflowPipeline? = nil,
        transcriber: @escaping SpokenWorkflowPipeline.Transcriber,
        processingLabelResolver: @escaping () -> String? = { nil },
        improver: @escaping Improver = { text, settings, providerMode in
            let result = try await LLMService.improve(
                text: text,
                settings: settings,
                providerMode: providerMode
            )
            return RewriteStepResult(text: result, completionLabel: nil)
        }
    ) -> SpokenRewriteWorkflow {
        SpokenRewriteWorkflow(
            type: .textImprover,
            customTerms: settings.customTerms,
            language: language,
            rewritingMessage: "Text wird verbessert ...",
            pipeline: pipeline,
            transcriber: transcriber,
            processingLabelResolver: processingLabelResolver,
            rewrite: { transcript in
                try await improver(transcript, settings, providerMode)
            }
        )
    }

    static func dampfAblassen(
        settings: DampfAblassenSettings,
        customTerms: [String] = [],
        language: String = "de",
        providerMode: RewriteProviderMode = .auto,
        pipeline: SpokenWorkflowPipeline? = nil,
        transcriber: @escaping SpokenWorkflowPipeline.Transcriber,
        processingLabelResolver: @escaping () -> String? = { nil },
        rewriter: @escaping DampfAblassenRewriter = { text, settings, providerMode in
            let result = try await LLMService.dampfAblassen(
                text: text,
                systemPrompt: settings.systemPrompt,
                providerMode: providerMode
            )
            return RewriteStepResult(text: result, completionLabel: nil)
        }
    ) -> SpokenRewriteWorkflow {
        SpokenRewriteWorkflow(
            type: .dampfAblassen,
            customTerms: customTerms,
            language: language,
            rewritingMessage: "Wird umformuliert ...",
            noSpeechSentinel: "KEINE_AUFNAHME_ERKANNT",
            pipeline: pipeline,
            transcriber: transcriber,
            processingLabelResolver: processingLabelResolver,
            rewrite: { transcript in
                try await rewriter(transcript, settings, providerMode)
            }
        )
    }

    static func emojiText(
        settings: EmojiTextSettings,
        customTerms: [String] = [],
        language: String = "de",
        providerMode: RewriteProviderMode = .auto,
        pipeline: SpokenWorkflowPipeline? = nil,
        transcriber: @escaping SpokenWorkflowPipeline.Transcriber,
        processingLabelResolver: @escaping () -> String? = { nil },
        rewriter: @escaping EmojiTextRewriter = { text, settings, providerMode in
            let result = try await LLMService.addEmojis(
                text: text,
                settings: settings,
                providerMode: providerMode
            )
            return RewriteStepResult(text: result, completionLabel: nil)
        }
    ) -> SpokenRewriteWorkflow {
        SpokenRewriteWorkflow(
            type: .emojiText,
            customTerms: customTerms,
            language: language,
            rewritingMessage: "Emojis werden eingefügt ...",
            noSpeechSentinel: "KEINE_AUFNAHME_ERKANNT",
            pipeline: pipeline,
            transcriber: transcriber,
            processingLabelResolver: processingLabelResolver,
            rewrite: { transcript in
                try await rewriter(transcript, settings, providerMode)
            }
        )
    }
}
