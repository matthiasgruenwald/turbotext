import Foundation
import AppKit
import Observation
import OSLog

private let transcriptionLogger = Logger(subsystem: "app.turbotext.mac", category: "Transcription")

private func elapsedMilliseconds(since start: Date, until end: Date = Date()) -> Int {
    Int((end.timeIntervalSince(start) * 1000).rounded())
}

@Observable
@MainActor
final class TranscriptionWorkflow: Workflow {
    let type: WorkflowType
    var phase: WorkflowPhase = .idle {
        didSet { onPhaseChange?(phase) }
    }
    var onOutput: WorkflowOutputHandler?
    var onPhaseChange: WorkflowPhaseChangeHandler?

    private let pipeline = SpokenWorkflowPipeline()
    private let customTerms: [String]
    private let language: String
    private let backend: TranscriptionBackend
    private let localModelName: String
    private var transcriptionTask: Task<Void, Never>?

    init(
        type: WorkflowType = .transcription,
        customTerms: [String] = [],
        language: String = "de",
        backend: TranscriptionBackend = .remote,
        localModelName: String = LocalTranscriptionService.recommendedFastModelName
    ) {
        self.type = type
        self.customTerms = customTerms
        self.language = language
        self.backend = backend
        self.localModelName = localModelName
    }

    func start() {
        switch pipeline.startRecording() {
        case .success:
            phase = .running("Aufnahme läuft ...")
        case .failure(let error):
            phase = .error(error.localizedDescription)
            return
        }
    }

    func stop() {
        if pipeline.isRecording {
            switch pipeline.stopRecording() {
            case .success(let recording):
                transcribe(recording)
            case .failure(let error):
                phase = .error(error.localizedDescription)
            }
        } else {
            transcriptionTask?.cancel()
            phase = .idle
        }
    }

    func reset() {
        transcriptionTask?.cancel()
        pipeline.resetRecording()
        phase = .idle
    }

    var isRecording: Bool { pipeline.isRecording }
    var audioLevel: Float { pipeline.audioLevel }

    private func transcribe(_ recording: SpokenWorkflowPipeline.Recording) {
        phase = .running(backend == .local ? "Wird lokal transkribiert ..." : "Wird transkribiert ...")
        let requestLanguage = language
        let stopTime = Date()

        transcriptionTask = Task(priority: .userInitiated) {
            let requestStart = Date()
            do {
                let text = try await pipeline.transcribeRecording(
                    recording,
                    customTerms: customTerms,
                    language: requestLanguage,
                    transcriber: { audioURL, duration, terms, language in
                        switch backend {
                        case .remote:
                            return try await TranscriptionService.transcribe(
                                audioURL: audioURL,
                                durationSeconds: duration,
                                customTerms: terms,
                                language: language
                            ).text
                        case .local:
                            return try await LocalTranscriptionService.shared.transcribe(
                                audioURL: audioURL,
                                language: language,
                                modelName: localModelName
                            )
                        }
                    }
                )
                try Task.checkCancellation()

                let responseReceivedAt = Date()

                transcriptionLogger.info(
                    "Transcription ready in \(elapsedMilliseconds(since: stopTime, until: responseReceivedAt)) ms (request \(elapsedMilliseconds(since: requestStart, until: responseReceivedAt)) ms)"
                )
                phase = .done(text)
                onOutput?(text)
            } catch SpokenWorkflowPipeline.Error.noSpeech {
                transcriptionLogger.info(
                    "Transcription rejected short artifact after \(elapsedMilliseconds(since: stopTime)) ms"
                )
                phase = .error("Keine Aufnahme erkannt.")
            } catch {
                transcriptionLogger.error(
                    "Transcription failed after \(elapsedMilliseconds(since: stopTime)) ms: \(error.localizedDescription, privacy: .private)"
                )
                phase = .error(error.localizedDescription)
            }
        }
    }
}
