import Foundation

enum RecordingOverlayPhase: Equatable {
    case hidden
    case recording
    case processing
    case error
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
        errorElapsed: TimeInterval = 0
    ) {
        self.phase = phase
        self.anchor = anchor
        self.levelHistory = levelHistory
        self.silenceElapsed = silenceElapsed
        self.errorMessage = errorMessage
        self.errorElapsed = errorElapsed
    }

    /// Applies one `MenuBarStatus` observation. `resolveAnchor` is only consulted when
    /// transitioning from a non-recording phase into `.recording` (or into `.error`); while
    /// already `.recording`/`.processing`, `repositioned(to:)` is what moves the anchor
    /// (see `RecordingOverlayController.repositionIfNeeded()`), so this method's own anchor
    /// handling here is a one-time resolution, not a freeze for the rest of the lifetime.
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
        resolveErrorMessage: () -> String? = { nil }
    ) -> RecordingOverlayState {
        switch menuBarStatus {
        case .recording:
            guard phase != .recording else { return self }
            return RecordingOverlayState(phase: .recording, anchor: resolveAnchor(), levelHistory: [])
        case .processing, .success:
            guard phase == .recording || phase == .processing else { return self }
            return RecordingOverlayState(phase: .processing, anchor: anchor, levelHistory: levelHistory)
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
            case .recording, .processing:
                return .hidden
            }
        case .idle:
            guard phase != .error else { return self }
            return .hidden
        }
    }

    /// Moves the anchor while `.recording` or `.processing`, keeping every other field
    /// unchanged. Lets the overlay keep following the target app's text cursor (or
    /// re-sample the active screen's bottom center) after the initial `applying()`
    /// resolution, without disturbing level history, silence tracking, or phase.
    /// A no-op outside those two phases.
    func repositioned(to anchor: RecordingOverlayAnchor) -> RecordingOverlayState {
        guard phase == .recording || phase == .processing else { return self }
        guard anchor != self.anchor else { return self }
        return RecordingOverlayState(
            phase: phase,
            anchor: anchor,
            levelHistory: levelHistory,
            silenceElapsed: silenceElapsed,
            errorMessage: errorMessage,
            errorElapsed: errorElapsed
        )
    }

    func receivingLevel(_ level: Float, elapsed: TimeInterval = 0) -> RecordingOverlayState {
        guard phase == .recording else { return self }
        let clamped = min(max(level, 0), 1)
        let nextHistory = Array((levelHistory + [clamped]).suffix(Self.levelHistoryLimit))
        let nextSilence = clamped > Self.silenceLevelThreshold ? 0 : silenceElapsed + elapsed
        return RecordingOverlayState(phase: phase, anchor: anchor, levelHistory: nextHistory, silenceElapsed: nextSilence)
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
}
