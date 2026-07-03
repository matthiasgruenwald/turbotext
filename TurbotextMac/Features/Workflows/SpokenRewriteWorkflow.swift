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

    let pipeline: SpokenWorkflowPipeline
    private let customTerms: [String]
    private let language: String
    private let transcriber: SpokenWorkflowPipeline.Transcriber
    private let rewritingMessage: String
    private let noSpeechSentinel: String?
    private let rewrite: (String) async throws -> String
    private var processingTask: Task<Void, Never>?

    init(
        type: WorkflowType,
        customTerms: [String],
        language: String,
        rewritingMessage: String,
        noSpeechSentinel: String? = nil,
        pipeline: SpokenWorkflowPipeline? = nil,
        transcriber: @escaping SpokenWorkflowPipeline.Transcriber,
        rewrite: @escaping (String) async throws -> String
    ) {
        self.type = type
        self.customTerms = customTerms
        self.language = language
        self.rewritingMessage = rewritingMessage
        self.noSpeechSentinel = noSpeechSentinel
        self.pipeline = pipeline ?? SpokenWorkflowPipeline()
        self.transcriber = transcriber
        self.rewrite = rewrite
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

// MARK: - Factory Methods

extension SpokenRewriteWorkflow {
    typealias Improver = (String, TextImprovementSettings, RewriteProviderMode) async throws -> String
    typealias DampfAblassenRewriter = (String, DampfAblassenSettings, RewriteProviderMode) async throws -> String
    typealias EmojiTextRewriter = (String, EmojiTextSettings, RewriteProviderMode) async throws -> String

    static func textImprovement(
        settings: TextImprovementSettings,
        language: String = "de",
        providerMode: RewriteProviderMode = .auto,
        pipeline: SpokenWorkflowPipeline? = nil,
        transcriber: @escaping SpokenWorkflowPipeline.Transcriber,
        improver: @escaping Improver = { text, settings, providerMode in
            try await LLMService.improve(
                text: text,
                settings: settings,
                providerMode: providerMode
            )
        }
    ) -> SpokenRewriteWorkflow {
        SpokenRewriteWorkflow(
            type: .textImprover,
            customTerms: settings.customTerms,
            language: language,
            rewritingMessage: "Text wird verbessert ...",
            pipeline: pipeline,
            transcriber: transcriber,
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
        rewriter: @escaping DampfAblassenRewriter = { text, settings, providerMode in
            try await LLMService.dampfAblassen(
                text: text,
                systemPrompt: settings.systemPrompt,
                providerMode: providerMode
            )
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
        rewriter: @escaping EmojiTextRewriter = { text, settings, providerMode in
            try await LLMService.addEmojis(
                text: text,
                settings: settings,
                providerMode: providerMode
            )
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
            rewrite: { transcript in
                try await rewriter(transcript, settings, providerMode)
            }
        )
    }
}
