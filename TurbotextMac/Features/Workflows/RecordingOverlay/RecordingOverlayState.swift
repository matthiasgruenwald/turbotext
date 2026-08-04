import Foundation

enum RecordingOverlayPhase: Equatable {
    case hidden
    case recording
    case processing
    case error
    /// Shows the rewrite completion label for a few seconds after the result was
    /// pasted (#128), independent of the underlying workflow having already reset.
    case completion
    /// Engine failure during live dictation after rescued segments were pasted
    /// (ADR 0005). Unlike `.error` it never auto-dismisses — the text was inserted
    /// without final post-processing, so the user must acknowledge it actively.
    case bergungError
    /// Paste retry window ran out without the target becoming frontmost (#176). The
    /// text is safely on the clipboard but nothing was inserted; like `.bergungError`
    /// it never auto-dismisses — the user must acknowledge it actively.
    case pasteError
}

/// Structured live-dictate transcript shown by the pill while `.recording` (#150):
/// finalized engine text plus the volatile tail Apple Speech still rewrites.
struct LiveTranscriptDisplay: Equatable {
    var finalText = ""
    var volatileText = ""
    var maxLines = 1

    var isEmpty: Bool { finalText.isEmpty && volatileText.isEmpty }

    var displayText: String {
        if volatileText.isEmpty { return finalText }
        if finalText.isEmpty { return volatileText }
        return finalText + " " + volatileText
    }
}

/// Immutable snapshot of what the signal pill should show. Derived purely
/// from `MenuBarStatus` transitions plus sampled audio levels, so it can be
/// unit-tested without AppKit windows or a real workflow.
struct RecordingOverlayState: Equatable {
    /// 10 samples/s × 15 s — the wider window keeps the waveform meaningful across
    /// engine delivery bursts instead of showing only the last 3 s (#158).
    static let levelHistoryLimit = 150
    /// One level sample per poll tick; the engine-progress marker converts the lag
    /// into bar indices at exactly this cadence (#158 package 4).
    static let levelSampleInterval: TimeInterval = 0.1
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
    /// Structured live-dictate transcript shown while `.recording` (#150). Always `nil`
    /// for non-streaming backends (WhisperKit/Groq) since nothing ever updates it.
    let liveTranscriptDisplay: LiveTranscriptDisplay?
    /// Seconds of fed audio the live engine has not decoded yet (#158 package 4):
    /// fed audio seconds minus `volatileRange.end`. Drives the two-colored waveform.
    /// `nil` for non-streaming backends and before the engine's first volatile range.
    let transcriptionLag: TimeInterval?
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
        phase == .recording
            && (liveTranscriptDisplay?.isEmpty ?? true)
            && silenceElapsed + Self.elapsedTimeTolerance >= Self.silenceHintDelay
    }

    /// How many of the newest bars (counted from the right edge) the engine has not
    /// decoded yet (#158 package 4). Relative arithmetic only — fed audio seconds
    /// minus `volatileRange.end` — so nothing can drift against wall-clock time.
    /// `nil` lag keeps the strip single-colored until the engine reports progress.
    static func unheardBarCount(forLag lag: TimeInterval?) -> Int? {
        guard let lag else { return nil }
        let bars = Int((lag / levelSampleInterval).rounded())
        return min(max(bars, 0), levelHistoryLimit)
    }

    init(
        phase: RecordingOverlayPhase,
        anchor: RecordingOverlayAnchor?,
        levelHistory: [Float],
        silenceElapsed: TimeInterval = 0,
        errorMessage: String? = nil,
        errorElapsed: TimeInterval = 0,
        liveTranscriptDisplay: LiveTranscriptDisplay? = nil,
        transcriptionLag: TimeInterval? = nil,
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
        self.liveTranscriptDisplay = liveTranscriptDisplay
        self.transcriptionLag = transcriptionLag
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
    /// `.hidden`, i.e. recording never visibly began) surfaces as an `.error` phase —
    /// but only when an error message is known; a message-less `.error` status stays
    /// hidden so an already-acknowledged failure (#176) cannot resurface unexplained.
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
                liveTranscriptDisplay: liveTranscriptDisplay,
                transcriptionLag: transcriptionLag,
                processingLabel: processingLabel ?? resolveProcessingLabel()
            )
        case .error:
            switch phase {
            case .hidden:
                // Only a known error message may surface a pill out of `.hidden`; a
                // message-less `.error` (e.g. the paste-retry exhaustion status #176,
                // which the pill already acknowledged via `.pasteError`) would otherwise
                // reappear as an unexplained error right after being dismissed.
                guard let message = resolveErrorMessage() else { return self }
                return RecordingOverlayState(
                    phase: .error, anchor: resolveAnchor(), levelHistory: [], errorMessage: message
                )
            case .error, .bergungError, .pasteError:
                // Ignore: this is the orchestrator repeating the still-ongoing error on
                // every poll, not a distinguishable new attempt (see doc comment above).
                return self
            case .recording, .processing, .completion:
                return .hidden
            }
        case .idle:
            switch phase {
            case .error, .completion, .bergungError, .pasteError:
                // `.error` waits for its own timer/manual dismiss; `.completion` likewise
                // (see below); `.bergungError` and `.pasteError` wait for manual dismiss
                // only — a repeated `.idle` observation must not cut any of them short.
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
            liveTranscriptDisplay: liveTranscriptDisplay,
            transcriptionLag: transcriptionLag,
            signalReceived: signalReceived || clamped > Self.silenceLevelThreshold
        )
    }

    /// Applies a fresh structured live transcript from the streaming callback (#150).
    /// Also accepted while `.processing` so the drain tail stays visible (#159).
    func receivingLiveTranscript(_ display: LiveTranscriptDisplay) -> RecordingOverlayState {
        guard phase == .recording || phase == .processing else { return self }
        guard display != liveTranscriptDisplay else { return self }
        return RecordingOverlayState(
            phase: phase, anchor: anchor, levelHistory: levelHistory, silenceElapsed: silenceElapsed,
            liveTranscriptDisplay: display, transcriptionLag: transcriptionLag,
            processingLabel: processingLabel,
            signalReceived: signalReceived
        )
    }

    /// Applies a fresh engine-progress sample (#158 package 4). Also accepted while
    /// `.processing` so the frozen strip shows the drain catching up to the right edge.
    func receivingTranscriptionLag(_ lag: TimeInterval?) -> RecordingOverlayState {
        guard phase == .recording || phase == .processing else { return self }
        guard lag != transcriptionLag else { return self }
        return RecordingOverlayState(
            phase: phase, anchor: anchor, levelHistory: levelHistory, silenceElapsed: silenceElapsed,
            liveTranscriptDisplay: liveTranscriptDisplay,
            transcriptionLag: lag, processingLabel: processingLabel,
            signalReceived: signalReceived
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

    /// Enters the persistent rescue-failure state after an engine error mid-dictation
    /// inserted the rescued segments (ADR 0005). Only live recording can be rescued.
    func enteringBergungError(message: String?) -> RecordingOverlayState {
        guard phase == .recording else { return self }
        return RecordingOverlayState(
            phase: .bergungError, anchor: anchor, levelHistory: levelHistory, errorMessage: message
        )
    }

    /// User-initiated close of the rescue-failure state — the only way it ends.
    func dismissingBergungError() -> RecordingOverlayState {
        guard phase == .bergungError else { return self }
        return .hidden
    }

    /// Enters the persistent paste-failure state (#176). Reachable from every phase:
    /// the failure arrives after output delivery, when the pill may already show
    /// `.completion` or be `.hidden` again because the workflow cleanup ran first.
    /// The anchor is kept when one exists, resolved fresh otherwise.
    func enteringPasteError(
        message: String?,
        resolveAnchor: () -> RecordingOverlayAnchor
    ) -> RecordingOverlayState {
        guard phase != .pasteError else { return self }
        return RecordingOverlayState(
            phase: .pasteError,
            anchor: anchor ?? resolveAnchor(),
            levelHistory: levelHistory,
            errorMessage: message
        )
    }

    /// User-initiated close of the paste-failure state — the only way it ends.
    func dismissingPasteError() -> RecordingOverlayState {
        guard phase == .pasteError else { return self }
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
