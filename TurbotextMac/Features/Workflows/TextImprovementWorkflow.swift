import Foundation
import AppKit
import Observation

@Observable
@MainActor
final class TextImprovementWorkflow: Workflow {
    typealias Improver = (String, TextImprovementSettings, RewriteProviderMode) async throws -> String

    let type = WorkflowType.textImprover
    var phase: WorkflowPhase = .idle {
        didSet { onPhaseChange?(phase) }
    }
    var onOutput: WorkflowOutputHandler?
    var onPhaseChange: WorkflowPhaseChangeHandler?

    private let pipeline: SpokenWorkflowPipeline
    private let settings: TextImprovementSettings
    private let language: String
    private let providerMode: RewriteProviderMode
    private let transcriber: SpokenWorkflowPipeline.Transcriber
    private let improver: Improver
    private var processingTask: Task<Void, Never>?

    init(
        settings: TextImprovementSettings,
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
        improver: @escaping Improver = { text, settings, providerMode in
            try await LLMService.improve(
                text: text,
                settings: settings,
                providerMode: providerMode
            )
        }
    ) {
        self.settings = settings
        self.language = language
        self.providerMode = providerMode
        self.pipeline = pipeline ?? SpokenWorkflowPipeline()
        self.transcriber = transcriber
        self.improver = improver
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

    // MARK: - Two-Phase Processing: Whisper -> GPT

    private func processRecording(_ recording: SpokenWorkflowPipeline.Recording) {
        phase = .running("Wird transkribiert ...")

        processingTask = Task {
            do {
                let rawText = try await pipeline.transcribeRecording(
                    recording,
                    customTerms: settings.customTerms,
                    language: language,
                    transcriber: transcriber
                )
                try Task.checkCancellation()

                phase = .running("Text wird verbessert ...")
                let improved = try await improver(rawText, settings, providerMode)

                let cleanedImproved = TranscriptionQualityService.cleanedTranscript(improved)
                phase = .done(cleanedImproved)
                onOutput?(cleanedImproved)
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
