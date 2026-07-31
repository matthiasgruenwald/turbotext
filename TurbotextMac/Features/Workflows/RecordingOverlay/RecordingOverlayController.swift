import AppKit
import SwiftUI

/// Non-activating panel that never becomes key/main, so showing it can never
/// steal focus or keyboard input from the target app.
private final class RecordingOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Sole owner of the cursor-anchored signal pill panel. Polls `WorkflowOrchestrator`
/// state on a lightweight timer rather than wiring into its single-slot callbacks
/// (`onWorkflowFinished`/`onWillPaste`), which `WorkflowLifecycleManager` already owns.
@MainActor
final class RecordingOverlayController {
    private static let pollInterval: TimeInterval = 0.1

    private let orchestrator: WorkflowOrchestrator
    private let modeProvider: () -> RecordingOverlayMode
    private let anchorResolver: () -> RecordingOverlayAnchor
    private let levelProvider: () -> Float?
    private let errorMessageProvider: () -> String?
    private let partialTranscriptProvider: () -> String?
    private let processingLabelProvider: () -> String?
    private let completionLabelProvider: () -> String?

    private(set) var state: RecordingOverlayState = .hidden
    private var panel: NSPanel?
    private var hostingView: NSHostingView<RecordingOverlaySignalPillView>?
    private var pollTimer: Timer?

    /// Test-only escape hatch to assert real panel configuration (focus/space/interaction
    /// behavior) without duplicating that setup in a fake.
    var debugPanel: NSPanel? { panel }

    init(
        orchestrator: WorkflowOrchestrator,
        modeProvider: @escaping () -> RecordingOverlayMode,
        anchorResolver: (() -> RecordingOverlayAnchor)? = nil,
        targetScreenBottomCenterProvider: @escaping (pid_t) -> CGPoint? = RecordingOverlayAnchorResolver.targetWindowBottomCenter,
        screenBottomCenterProvider: @escaping () -> CGPoint = { RecordingOverlayAnchorResolver.primaryScreenBottomCenter() },
        levelProvider: (() -> Float?)? = nil,
        errorMessageProvider: (() -> String?)? = nil,
        partialTranscriptProvider: (() -> String?)? = nil,
        processingLabelProvider: (() -> String?)? = nil,
        completionLabelProvider: (() -> String?)? = nil
    ) {
        self.orchestrator = orchestrator
        self.modeProvider = modeProvider
        self.anchorResolver = anchorResolver ?? { [weak orchestrator] in
            switch modeProvider() {
            case .off:
                return RecordingOverlayAnchor(point: screenBottomCenterProvider(), source: .screenBottomCenter)
            case .screenBottomCenter:
                let point = orchestrator?.activePasteTargetProcessIdentifier
                    .flatMap(targetScreenBottomCenterProvider) ?? screenBottomCenterProvider()
                return RecordingOverlayAnchor(point: point, source: .screenBottomCenter)
            }
        }
        self.levelProvider = levelProvider ?? { [weak orchestrator] in orchestrator?.activeWorkflow?.audioLevel }
        self.errorMessageProvider = errorMessageProvider ?? { [weak orchestrator] in orchestrator?.lastErrorMessage }
        self.partialTranscriptProvider = partialTranscriptProvider ?? { [weak orchestrator] in orchestrator?.lastPartialTranscript }
        self.processingLabelProvider = processingLabelProvider ?? { [weak orchestrator] in orchestrator?.lastProcessingLabel }
        self.completionLabelProvider = completionLabelProvider ?? { [weak orchestrator] in orchestrator?.lastCompletionLabel }
    }

    func start() {
        stop()
        pollTimer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    /// Exposed for tests: applies one polling step without a real `Timer`.
    func tick() {
        guard modeProvider() != .off else {
            applyHiddenAndReset()
            return
        }

        let previousPhase = state.phase
        let previousAnchor = state.anchor
        state = state.applying(
            menuBarStatus: orchestrator.menuBarStatus,
            resolveAnchor: anchorResolver,
            resolveErrorMessage: errorMessageProvider,
            resolveProcessingLabel: processingLabelProvider,
            resolveCompletionLabel: completionLabelProvider
        )

        switch state.phase {
        case .recording:
            if let level = levelProvider() {
                state = state.receivingLevel(level, elapsed: Self.pollInterval)
            }
            if let partialTranscript = partialTranscriptProvider() {
                state = state.receivingPartialTranscript(partialTranscript)
            }
        case .processing:
            break
        case .completion:
            state = state.advancingCompletion(by: Self.pollInterval)
        case .error:
            state = state.advancingError(by: Self.pollInterval)
        case .hidden:
            break
        }

        let anchorChanged = state.anchor != previousAnchor
        guard state.phase != previousPhase || state.phase == .recording || anchorChanged else { return }
        render()
    }

    /// Manual close of a visible start error, e.g. from a click on the pill.
    func dismissError() {
        guard state.phase == .error else { return }
        state = state.dismissingError()
        render()
    }

    /// Manual dismissal of a visible completion label, e.g. from a click on the pill.
    /// Callers wire `onCompletionLabelDismissed` to persist the "don't show again" choice.
    func dismissCompletionLabel() {
        guard state.phase == .completion else { return }
        state = state.dismissingCompletion()
        render()
        onCompletionLabelDismissed?()
    }

    /// Fired when the user dismisses a visible completion label, so the host can persist
    /// `AppSettings.hideRewriteCompletionLabel` (#128).
    var onCompletionLabelDismissed: (() -> Void)?

    private func applyHiddenAndReset() {
        guard state.phase != .hidden else { return }
        state = .hidden
        render()
    }

    private func render() {
        switch state.phase {
        case .hidden:
            panel?.orderOut(nil)
        case .recording, .processing, .error, .completion:
            let activePanel = panel ?? makePanel()
            panel = activePanel
            // The error and completion pills accept clicks (manual dismiss); every other
            // state must stay click-through so it never steals input from the target app.
            activePanel.ignoresMouseEvents = state.phase != .error && state.phase != .completion
            updateContent(of: activePanel)
            positionPanel(activePanel)
            activePanel.orderFrontRegardless()
        }
    }

    private func makePanel() -> NSPanel {
        let panel = RecordingOverlayPanel(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.auxiliary, .fullScreenAuxiliary, .canJoinAllSpaces, .ignoresCycle]
        return panel
    }

    private func updateContent(of panel: NSPanel) {
        let pill = RecordingOverlaySignalPillView(
            phase: state.phase,
            levelHistory: state.levelHistory,
            showsSilenceHint: state.showsSilenceHint,
            signalReceived: state.signalReceived,
            errorMessage: state.errorMessage,
            partialTranscript: state.partialTranscript,
            processingLabel: state.processingLabel,
            completionLabel: state.completionLabel,
            onDismissError: { [weak self] in self?.dismissError() },
            onDismissCompletionLabel: { [weak self] in self?.dismissCompletionLabel() }
        )
        // Reuse the hosting view and update rootView in place. Recreating it on
        // every poll tick (10x/s while recording) tore down SwiftUI's AttributeGraph
        // mid-transaction and crashed with EXC_BAD_ACCESS.
        let activeHostingView: NSHostingView<RecordingOverlaySignalPillView>
        if let hostingView {
            hostingView.rootView = pill
            activeHostingView = hostingView
        } else {
            let newHostingView = NSHostingView(rootView: pill)
            hostingView = newHostingView
            panel.contentView = newHostingView
            activeHostingView = newHostingView
        }
        let fittingSize = activeHostingView.fittingSize
        activeHostingView.frame = NSRect(origin: .zero, size: fittingSize)
        panel.setContentSize(fittingSize)
    }

    private func positionPanel(_ panel: NSPanel) {
        guard let anchor = state.anchor else { return }
        switch anchor.source {
        case .screenBottomCenter:
            // The anchor point is the desired horizontal center, not a left edge.
            let origin = NSPoint(x: anchor.point.x - panel.frame.width / 2, y: anchor.point.y)
            panel.setFrameOrigin(origin)
        }
    }
}
