import Foundation
import AppKit
import Observation

@Observable
@MainActor
final class EmojiTextWorkflow: Workflow {
    typealias Rewriter = (String, EmojiTextSettings, RewriteProviderMode) async throws -> String

    let type = WorkflowType.emojiText
    var phase: WorkflowPhase = .idle {
        didSet { onPhaseChange?(phase) }
    }
    var onOutput: WorkflowOutputHandler?
    var onPhaseChange: WorkflowPhaseChangeHandler?

    private let pipeline: SpokenWorkflowPipeline
    private let settings: EmojiTextSettings
    private let customTerms: [String]
    private let language: String
    private let providerMode: RewriteProviderMode
    private let transcriber: SpokenWorkflowPipeline.Transcriber
    private let rewriter: Rewriter
    private var processingTask: Task<Void, Never>?

    init(
        settings: EmojiTextSettings,
        customTerms: [String] = [],
        language: String = "de",
        providerMode: RewriteProviderMode = .auto,
        pipeline: SpokenWorkflowPipeline? = nil,
        transcriber: @escaping SpokenWorkflowPipeline.Transcriber = { audioURL, duration, terms, language in
            try await TranscriptionService.transcribe(
                audioURL: audioURL,
                durationSeconds: duration,
                customTerms: terms,
                language: language
            ).text
        },
        rewriter: @escaping Rewriter = { text, settings, providerMode in
            try await LLMService.addEmojis(
                text: text,
                settings: settings,
                providerMode: providerMode
            )
        }
    ) {
        self.settings = settings
        self.customTerms = customTerms
        self.language = language
        self.providerMode = providerMode
        self.pipeline = pipeline ?? SpokenWorkflowPipeline()
        self.transcriber = transcriber
        self.rewriter = rewriter
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
            phase = .idle
        }
    }

    func reset() {
        processingTask?.cancel()
        pipeline.resetRecording()
        phase = .idle
    }

    // MARK: - Two-Phase Processing: Whisper -> Emoji

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

                phase = .running("Emojis werden eingefügt ...")

                let result = try await rewriter(rawText, settings, providerMode)
                let cleanedResult = TranscriptionQualityService.cleanedTranscript(result)
                guard cleanedResult != "KEINE_AUFNAHME_ERKANNT" else {
                    phase = .error("Keine Aufnahme erkannt.")
                    return
                }
                phase = .done(cleanedResult)
                onOutput?(cleanedResult)
            } catch SpokenWorkflowPipeline.Error.noSpeech {
                phase = .error("Keine Aufnahme erkannt.")
            } catch {
                phase = .error(error.localizedDescription)
            }
        }
    }
}
