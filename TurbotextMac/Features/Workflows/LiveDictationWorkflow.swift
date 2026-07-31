import AVFAudio
import Foundation
import Observation

@available(macOS 26, *)
@Observable
@MainActor
final class LiveDictationWorkflow: Workflow {
    let type: WorkflowType
    var phase: WorkflowPhase = .idle {
        didSet { onPhaseChange?(phase) }
    }
    var onOutput: WorkflowOutputHandler?
    var onPhaseChange: WorkflowPhaseChangeHandler?
    private(set) var processingLabel: String?
    private(set) var completionLabel: String?

    var isRecording: Bool { pipeline.isRecording }
    var audioLevel: Float { pipeline.audioLevel }

    private let pipeline: SpokenWorkflowPipeline
    private let session: LiveTranscriptionSession
    private let isSmoothingActive: Bool
    private let rewritingMessage: String
    private let rewrite: ((String) async throws -> RewriteStepResult)?
    private let processingLabelResolver: () -> String?
    private let onLiveTranscriptUpdate: ((LiveTranscriptDisplay) -> Void)?
    private let onBergung: ((String?) -> Void)?
    private var processingTask: Task<Void, Never>?

    init(
        type: WorkflowType,
        session: LiveTranscriptionSession,
        isSmoothingActive: Bool = false,
        pipeline: SpokenWorkflowPipeline? = nil,
        rewritingMessage: String = "Wird verarbeitet ...",
        rewrite: ((String) async throws -> RewriteStepResult)? = nil,
        processingLabelResolver: @escaping () -> String? = { nil },
        onLiveTranscriptUpdate: ((LiveTranscriptDisplay) -> Void)? = nil,
        onBergung: ((String?) -> Void)? = nil
    ) {
        self.type = type
        self.session = session
        self.isSmoothingActive = isSmoothingActive
        self.pipeline = pipeline ?? SpokenWorkflowPipeline()
        self.rewritingMessage = rewritingMessage
        self.rewrite = rewrite
        self.processingLabelResolver = processingLabelResolver
        self.onLiveTranscriptUpdate = onLiveTranscriptUpdate
        self.onBergung = onBergung
    }

    func start() {
        processingLabel = nil
        completionLabel = nil

        switch pipeline.startRecording() {
        case .success:
            guard let format = pipeline.inputFormat else {
                phase = .error("Audioformat nicht verfügbar.")
                return
            }
            pipeline.onBuffer = { [weak session] buffer in
                session?.feed(buffer: buffer)
            }
            Task { [weak session] in
                try? await session?.start(sourceFormat: format)
            }
            phase = .running("Aufnahme läuft ...")
            observeSession()
        case .failure(let error):
            phase = .error(error.localizedDescription)
        }
    }

    func stop() {
        if pipeline.isRecording {
            pipeline.onBuffer = nil
            session.finish()
            _ = pipeline.stopRecording()
            processFinalText()
        } else {
            processingTask?.cancel()
            processingTask = nil
            session.cancel()
            phase = .idle
        }
    }

    func reset() {
        processingTask?.cancel()
        processingTask = nil
        session.cancel()
        pipeline.resetRecording()
        processingLabel = nil
        completionLabel = nil
        phase = .idle
    }

    private func processFinalText() {
        let text = session.finalizeText()
        guard !text.isEmpty else {
            phase = .error("Keine Aufnahme erkannt.")
            return
        }

        guard let rewrite else {
            let cleaned = TranscriptionQualityService.cleanedTranscript(text)
            phase = .done(cleaned)
            onOutput?(cleaned)
            return
        }

        processingLabel = processingLabelResolver()
        phase = .running(rewritingMessage)
        processingTask = Task {
            do {
                let result = try await rewrite(text)
                try Task.checkCancellation()
                let cleaned = TranscriptionQualityService.cleanedTranscript(result.text)
                completionLabel = result.completionLabel
                phase = .done(cleaned)
                onOutput?(cleaned)
            } catch is CancellationError {
                return
            } catch {
                phase = .error(error.localizedDescription)
            }
        }
    }

    private func handleBergung(message: String?) {
        guard isRecording else { return }
        pipeline.onBuffer = nil
        if pipeline.isRecording {
            _ = pipeline.stopRecording()
        }
        let text = session.finalizeText()
        onBergung?(message)
        guard !text.isEmpty else {
            phase = .error(message ?? "Aufnahme fehlgeschlagen.")
            return
        }
        let cleaned = TranscriptionQualityService.cleanedTranscript(text)
        phase = .done(cleaned)
        onOutput?(cleaned)
    }

    private func observeSession() {
        withObservationTracking {
            _ = session.phase
            _ = session.finalText
            _ = session.volatileText
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.handleSessionChange()
            }
        }
    }

    private func handleSessionChange() {
        switch session.phase {
        case .failed(let message, isBergung: true):
            handleBergung(message: message)
        case .failed(let message, isBergung: false):
            if pipeline.isRecording {
                pipeline.onBuffer = nil
                _ = pipeline.stopRecording()
            }
            phase = .error(message)
        default:
            guard isRecording else { return }
            relayTranscriptDisplay()
            observeSession()
        }
    }

    private func relayTranscriptDisplay() {
        let display = LiveTranscriptDisplay(
            finalText: session.finalText,
            volatileText: session.volatileText,
            isSmoothingActive: isSmoothingActive,
            maxLines: 3
        )
        onLiveTranscriptUpdate?(display)
    }
}
