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

    private(set) var state: RecordingOverlayState = .hidden
    private var panel: NSPanel?
    private var pollTimer: Timer?

    /// Test-only escape hatch to assert real panel configuration (focus/space/interaction
    /// behavior) without duplicating that setup in a fake.
    var debugPanel: NSPanel? { panel }

    init(
        orchestrator: WorkflowOrchestrator,
        modeProvider: @escaping () -> RecordingOverlayMode,
        anchorResolver: @escaping () -> RecordingOverlayAnchor = RecordingOverlayAnchorResolver.resolveWithSystemProviders,
        levelProvider: (() -> Float?)? = nil,
        errorMessageProvider: (() -> String?)? = nil
    ) {
        self.orchestrator = orchestrator
        self.modeProvider = modeProvider
        self.anchorResolver = anchorResolver
        self.levelProvider = levelProvider ?? { [weak orchestrator] in orchestrator?.activeWorkflow?.audioLevel }
        self.errorMessageProvider = errorMessageProvider ?? { [weak orchestrator] in orchestrator?.lastErrorMessage }
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
        state = state.applying(
            menuBarStatus: orchestrator.menuBarStatus,
            resolveAnchor: anchorResolver,
            resolveErrorMessage: errorMessageProvider
        )

        switch state.phase {
        case .recording:
            if let level = levelProvider() {
                state = state.receivingLevel(level, elapsed: Self.pollInterval)
            }
        case .error:
            state = state.advancingError(by: Self.pollInterval)
        case .hidden, .processing:
            break
        }

        guard state.phase != previousPhase || state.phase == .recording else { return }
        render()
    }

    /// Manual close of a visible start error, e.g. from a click on the pill.
    func dismissError() {
        guard state.phase == .error else { return }
        state = state.dismissingError()
        render()
    }

    private func applyHiddenAndReset() {
        guard state.phase != .hidden else { return }
        state = .hidden
        render()
    }

    private func render() {
        switch state.phase {
        case .hidden:
            panel?.orderOut(nil)
        case .recording, .processing, .error:
            let activePanel = panel ?? makePanel()
            panel = activePanel
            // Only the error pill accepts clicks (manual dismiss); every other state
            // must stay click-through so it never steals input from the target app.
            activePanel.ignoresMouseEvents = state.phase != .error
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
            errorMessage: state.errorMessage,
            onDismissError: { [weak self] in self?.dismissError() }
        )
        let hostingView = NSHostingView(rootView: pill)
        let fittingSize = hostingView.fittingSize
        hostingView.frame = NSRect(origin: .zero, size: fittingSize)
        panel.contentView = hostingView
        panel.setContentSize(fittingSize)
    }

    private func positionPanel(_ panel: NSPanel) {
        guard let anchor = state.anchor else { return }
        let origin = NSPoint(x: anchor.point.x, y: anchor.point.y + 12)
        panel.setFrameOrigin(origin)
    }
}
