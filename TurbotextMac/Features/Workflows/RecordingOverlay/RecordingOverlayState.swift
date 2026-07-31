import Foundation

enum RecordingOverlayPhase: Equatable {
    case hidden
    case recording
    case processing
    case error
    /// Shows the rewrite completion label for a few seconds after the result was
    /// pasted (#128), independent of the underlying workflow having already reset.
    case completion
}

/// Immutable snapshot of what the signal pill should show. Derived purely
/// from `MenuBarStatus` transitions plus sampled audio levels, so it can be
/// unit-tested without AppKit windows or a real workflow.
struct RecordingOverlayState: Equatable {
    static let levelHistoryLimit = 30
    /// How long a recording must show no usable signal before the silence hint appears.
    static let silenceHintDelay: TimeInterval = 5
    /// How long a known start error stays visible before it auto-dismisses.
    static let errorAutoDismissDelay: TimeInterval = 5
    /// How long the rewrite completion label stays visible before it auto-dismisses.
    static let completionAutoDismissDelay: TimeInterval = 3
    /// Normalized levels at or below this are treated as "no usable signal".
    static let silenceLevelThreshold: Float = 0.05
    /// Absorbs floating-point drift from repeatedly summing small poll intervals
    /// (e.g. 50x0.1 lands a hair under 5.0), so the 5s thresholds above fire on time.
    private static let elapsedTimeTolerance: TimeInterval = 0.001

    let phase: RecordingOverlayPhase
    let anchor: RecordingOverlayAnchor?
    let levelHistory: [Float]
    let silenceElapsed: TimeInterval
    let errorMessage: String?
    let errorElapsed: TimeInterval
    /// Progressive Apple Speech transcript shown while `.recording` (#128). Always `nil`
    /// for other transcription backends (WhisperKit/Groq) since nothing ever updates it.
    let partialTranscript: String?
    /// Resolved once when entering `.processing` (#128): "lokal" vs. "online mit ‹Anbieter›".
    let processingLabel: String?
    /// Shown while `.completion` (#128), e.g. "Text lokal verbessert · Apple Foundation Models".
    let completionLabel: String?
    let completionElapsed: TimeInterval
    let signalReceived: Bool

    static let hidden = RecordingOverlayState(
        phase: .hidden, anchor: nil, levelHistory: [], silenceElapsed: 0, errorMessage: nil, errorElapsed: 0
    )

    var showsSilenceHint: Bool {
        phase == .recording && silenceElapsed + Self.elapsedTimeTolerance >= Self.silenceHintDelay
    }

    init(
        phase: RecordingOverlayPhase,
        anchor: RecordingOverlayAnchor?,
        levelHistory: [Float],
        silenceElapsed: TimeInterval = 0,
        errorMessage: String? = nil,
        errorElapsed: TimeInterval = 0,
        partialTranscript: String? = nil,
        processingLabel: String? = nil,
        completionLabel: String? = nil,
        completionElapsed: TimeInterval = 0,
        signalReceived: Bool = false
    ) {
        self.phase = phase
        self.anchor = anchor
        self.levelHistory = levelHistory
        self.silenceElapsed = silenceElapsed
        self.errorMessage = errorMessage
        self.errorElapsed = errorElapsed
        self.partialTranscript = partialTranscript
        self.processingLabel = processingLabel
        self.completionLabel = completionLabel
        self.completionElapsed = completionElapsed
        self.signalReceived = signalReceived
    }

    /// Applies one `MenuBarStatus` observation. `resolveAnchor` is only consulted when
    /// transitioning from a non-recording phase into `.recording` (or into `.error`), so
    /// the overlay keeps the position chosen when the workflow begins.
    ///
    /// A known recording-start error (`.error` observed while the overlay was still
    /// `.hidden`, i.e. recording never visibly began) surfaces as an `.error` phase.
    /// An error observed mid-recording/processing still just hides, matching the
    /// pre-#107 behavior — that path covers post-start failures out of this issue's scope.
    ///
    /// Once `.error` is showing, a *repeated* `.error`/`.idle` observation is ignored:
    /// `WorkflowOrchestrator` repeats the same `.error` status on every poll and later
    /// resets itself to `.idle` on its own (~1.6s) internal timer, well before the
    /// pill's own 5s window — reacting to either would hide the pill early. Only
    /// `advancingError`/`dismissingError` (this state's own timer, or the user closing
    /// it) may end an unchanged error. A genuine new attempt still overrides it
    /// immediately once it starts recording: `.recording` always wins over `.error`.
    func applying(
        menuBarStatus: MenuBarStatus,
        resolveAnchor: () -> RecordingOverlayAnchor,
        resolveErrorMessage: () -> String? = { nil },
        resolveProcessingLabel: () -> String? = { nil },
        resolveCompletionLabel: () -> String? = { nil }
    ) -> RecordingOverlayState {
        switch menuBarStatus {
        case .recording:
            guard phase != .recording else { return self }
            return RecordingOverlayState(phase: .recording, anchor: resolveAnchor(), levelHistory: [])
        case .processing, .success:
            guard phase == .recording || phase == .processing else { return self }
            return RecordingOverlayState(
                phase: .processing, anchor: anchor, levelHistory: levelHistory,
                processingLabel: processingLabel ?? resolveProcessingLabel()
            )
        case .error:
            switch phase {
            case .hidden:
                return RecordingOverlayState(
                    phase: .error, anchor: resolveAnchor(), levelHistory: [], errorMessage: resolveErrorMessage()
                )
            case .error:
                // Ignore: this is the orchestrator repeating the still-ongoing error on
                // every poll, not a distinguishable new attempt (see doc comment above).
                return self
            case .recording, .processing, .completion:
                return .hidden
            }
        case .idle:
            switch phase {
            case .error, .completion:
                // `.error` waits for its own timer/manual dismiss; `.completion` likewise
                // (see below) — a repeated `.idle` observation must not cut either short.
                return self
            case .processing:
                guard let label = resolveCompletionLabel() else { return .hidden }
                return RecordingOverlayState(
                    phase: .completion, anchor: anchor, levelHistory: levelHistory, completionLabel: label
                )
            case .hidden, .recording:
                return .hidden
            }
        }
    }

    func receivingLevel(_ level: Float, elapsed: TimeInterval = 0) -> RecordingOverlayState {
        guard phase == .recording else { return self }
        let clamped = min(max(level, 0), 1)
        let nextHistory = Array((levelHistory + [clamped]).suffix(Self.levelHistoryLimit))
        let nextSilence = clamped > Self.silenceLevelThreshold ? 0 : silenceElapsed + elapsed
        return RecordingOverlayState(
            phase: phase, anchor: anchor, levelHistory: nextHistory, silenceElapsed: nextSilence,
            partialTranscript: partialTranscript,
            signalReceived: signalReceived || clamped > Self.silenceLevelThreshold
        )
    }

    /// Applies a fresh partial transcript from Apple Speech's progressive callback (#128).
    /// Ignored outside `.recording` — the field is meaningless once processing/rewriting begins.
    func receivingPartialTranscript(_ text: String) -> RecordingOverlayState {
        guard phase == .recording else { return self }
        guard text != partialTranscript else { return self }
        return RecordingOverlayState(
            phase: phase, anchor: anchor, levelHistory: levelHistory, silenceElapsed: silenceElapsed,
            partialTranscript: text
        )
    }

    /// Advances the auto-dismiss countdown for a visible error. Returns `.hidden` once
    /// `errorAutoDismissDelay` has elapsed.
    func advancingError(by elapsed: TimeInterval) -> RecordingOverlayState {
        guard phase == .error else { return self }
        let nextElapsed = errorElapsed + elapsed
        guard nextElapsed + Self.elapsedTimeTolerance < Self.errorAutoDismissDelay else { return .hidden }
        return RecordingOverlayState(
            phase: phase, anchor: anchor, levelHistory: levelHistory, errorMessage: errorMessage, errorElapsed: nextElapsed
        )
    }

    /// User-initiated close of a visible error, independent of the auto-dismiss timer.
    func dismissingError() -> RecordingOverlayState {
        guard phase == .error else { return self }
        return .hidden
    }

    /// Advances the auto-dismiss countdown for a visible completion label. Returns
    /// `.hidden` once `completionAutoDismissDelay` has elapsed.
    func advancingCompletion(by elapsed: TimeInterval) -> RecordingOverlayState {
        guard phase == .completion else { return self }
        let nextElapsed = completionElapsed + elapsed
        guard nextElapsed + Self.elapsedTimeTolerance < Self.completionAutoDismissDelay else { return .hidden }
        return RecordingOverlayState(
            phase: phase, anchor: anchor, levelHistory: levelHistory,
            completionLabel: completionLabel, completionElapsed: nextElapsed
        )
    }

    /// User-initiated dismissal of a visible completion label (#128), independent of the
    /// auto-dismiss timer — also used to permanently disable the label going forward.
    func dismissingCompletion() -> RecordingOverlayState {
        guard phase == .completion else { return self }
        return .hidden
    }
}
