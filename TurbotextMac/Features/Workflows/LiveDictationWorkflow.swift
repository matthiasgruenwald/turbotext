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
    var transcriptionLag: TimeInterval? { session.transcriptionLag }

    private let pipeline: SpokenWorkflowPipeline
    private let session: LiveTranscriptionSession
    private let maxLines: Int
    private let rewritingMessage: String
    private let smoothingPass: (@Sendable (String) async -> String?)?
    private let smoothingBudget: Duration
    private let smoothingMessage: String
    private let rewriteStage: RewriteStage?
    private let processingLabelResolver: () -> String?
    private let onLiveTranscriptUpdate: ((LiveTranscriptDisplay) -> Void)?
    private let onBergung: ((String?) -> Void)?
    private let fileFallbackTranscriber: (URL, TimeInterval) async throws -> String
    private let gracePeriod: Duration
    private var processingTask: Task<Void, Never>?
    private var graceTask: Task<Void, Never>?
    private var isDraining = false

    init(
        type: WorkflowType,
        session: LiveTranscriptionSession,
        smoothingPass: (@Sendable (String) async -> String?)? = nil,
        smoothingBudget: Duration = .seconds(5),
        smoothingMessage: String = "Glättet ...",
        maxLines: Int = 8,
        pipeline: SpokenWorkflowPipeline? = nil,
        gracePeriod: Duration = .milliseconds(250),
        rewritingMessage: String = "Wird verarbeitet ...",
        rewriteStage: RewriteStage? = nil,
        processingLabelResolver: @escaping () -> String? = { nil },
        onLiveTranscriptUpdate: ((LiveTranscriptDisplay) -> Void)? = nil,
        onBergung: ((String?) -> Void)? = nil,
        fileFallbackTranscriber: ((URL, TimeInterval) async throws -> String)? = nil
    ) {
        self.type = type
        self.session = session
        self.smoothingPass = smoothingPass
        self.smoothingBudget = smoothingBudget
        self.smoothingMessage = smoothingMessage
        self.maxLines = maxLines
        self.pipeline = pipeline ?? SpokenWorkflowPipeline()
        self.gracePeriod = gracePeriod
        self.rewritingMessage = rewritingMessage
        self.rewriteStage = rewriteStage
        self.processingLabelResolver = processingLabelResolver
        self.onLiveTranscriptUpdate = onLiveTranscriptUpdate
        self.onBergung = onBergung
        self.fileFallbackTranscriber = fileFallbackTranscriber ?? { url, duration in
            try await AppleSpeechTranscriptionService.transcribe(
                audioURL: url, duration: duration, customTerms: [], language: "de"
            )
        }
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
        if let graceTask {
            graceTask.cancel()
            self.graceTask = nil
            finalizeStop()
        } else if pipeline.isRecording {
            guard gracePeriod > .zero else {
                finalizeStop()
                return
            }
            // #160: the tap buffer (~93 ms) plus hardware latency would cut off the
            // tail of the utterance; keep capture + session feed alive briefly first.
            graceTask = Task {
                do {
                    try await Task.sleep(for: gracePeriod)
                } catch {
                    return
                }
                graceTask = nil
                finalizeStop()
            }
        } else {
            processingTask?.cancel()
            processingTask = nil
            isDraining = false
            session.cancel()
            phase = .idle
        }
    }

    private func finalizeStop() {
        guard pipeline.isRecording else { return }
        pipeline.onBuffer = nil
        session.finish()
        let recording = pipeline.stopRecording()
        isDraining = true
        phase = .running("Aufnahme läuft ...")
        processingTask = Task { await drainThenProcess(recording: recording) }
    }

    func reset() {
        graceTask?.cancel()
        graceTask = nil
        processingTask?.cancel()
        processingTask = nil
        isDraining = false
        session.cancel()
        pipeline.resetRecording()
        processingLabel = nil
        completionLabel = nil
        phase = .idle
    }

    private func drainThenProcess(recording: Result<SpokenWorkflowPipeline.Recording, SpokenWorkflowPipeline.Error>) async {
        let drained = await session.waitForDrain()
        var text = session.finalizeText()

        if !drained || text.isEmpty {
            if case .success(let rec) = recording {
                do {
                    let fallbackText = try await fileFallbackTranscriber(rec.url, rec.duration)
                    if !fallbackText.isEmpty {
                        text = fallbackText
                    }
                } catch is CancellationError {
                    isDraining = false
                    return
                } catch {}
            }
        }

        isDraining = false

        guard !text.isEmpty else {
            phase = .error("Keine Aufnahme erkannt.")
            return
        }

        if smoothingPass != nil {
            processingLabel = smoothingMessage
            phase = .running(smoothingMessage)
            if let smoothed = await smoothedWithinBudget(text) {
                text = smoothed
            }
            guard !Task.isCancelled else { return }
        }

        processText(text)
    }

    // #163: smoothing runs after the drain and never gates the insert — an over-budget
    // pass degrades to the raw text instead of blowing the completion deadline.
    // A task group would await its cancelled child until the model call unwinds
    // (LanguageModelSession.respond ignores cancellation), so the loser is detached.
    private func smoothedWithinBudget(_ text: String) async -> String? {
        guard let pass = smoothingPass else { return nil }
        let budget = smoothingBudget
        return await withCheckedContinuation { continuation in
            let resolver = SmoothingBudgetResolver(continuation: continuation)
            let work = Task {
                let result = await pass(text)
                await resolver.resolve(result)
            }
            Task {
                try? await Task.sleep(for: budget)
                work.cancel()
                await resolver.resolve(nil)
            }
        }
    }

    private func processText(_ text: String) {
        guard let rewriteStage else {
            let cleaned = TranscriptionQualityService.cleanedTranscript(text)
            phase = .done(cleaned)
            onOutput?(cleaned)
            return
        }

        processingLabel = processingLabelResolver()
        phase = .running(rewritingMessage)
        processingTask = Task {
            do {
                let outcome = try await rewriteStage.run(text)
                try Task.checkCancellation()
                switch outcome {
                case .rejected:
                    phase = .error("Keine Aufnahme erkannt.")
                case .rawInsertion(let finalText, let label):
                    completionLabel = label
                    phase = .done(finalText)
                    onOutput?(finalText)
                case .rewritten(let finalText, let label):
                    completionLabel = label
                    phase = .done(finalText)
                    onOutput?(finalText)
                }
            } catch is CancellationError {
                return
            } catch {
                phase = .error(error.localizedDescription)
            }
        }
    }

    private func handleBergung(message: String?) {
        guard isRecording else { return }
        graceTask?.cancel()
        graceTask = nil
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
            guard !isDraining else { return }
            graceTask?.cancel()
            graceTask = nil
            if pipeline.isRecording {
                pipeline.onBuffer = nil
                _ = pipeline.stopRecording()
            }
            phase = .error(message)
        default:
            guard isRecording || isDraining else { return }
            relayTranscriptDisplay()
            observeSession()
        }
    }

    private func relayTranscriptDisplay() {
        let display = LiveTranscriptDisplay(
            finalText: session.finalText,
            volatileText: session.volatileText,
            maxLines: maxLines
        )
        onLiveTranscriptUpdate?(display)
    }
}

private actor SmoothingBudgetResolver {
    private let continuation: CheckedContinuation<String?, Never>
    private var resolved = false

    init(continuation: CheckedContinuation<String?, Never>) {
        self.continuation = continuation
    }

    func resolve(_ value: String?) {
        guard !resolved else { return }
        resolved = true
        continuation.resume(returning: value)
    }
}
