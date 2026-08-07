import AppKit
import Observation
import OSLog

private let pasteLogger = Logger(subsystem: "app.turbotext.mac", category: "Paste")

/// Owns the lifecycle of the currently active `Workflow`: starting, stopping, resetting,
/// reacting to phase changes, and delivering output via paste-at-cursor (with retry).
///
/// `AppState` holds an instance and delegates to it; this type does not know about
/// `AppState` directly so it can be unit-tested by injecting a workflow factory and
/// a paste mechanism.
@Observable
@MainActor
final class WorkflowOrchestrator {
    private static let pasteRetryInitialAttempts = 22
    /// Slow tail appended to the fast retry phase; together they span ~1.5s so a target
    /// app that takes ~1s to regain the foreground after a window switch still receives
    /// the paste (#176).
    private static let pasteRetrySlowAttempts = 9
    private static let pasteRetrySlowInterval: TimeInterval = 0.1
    static let pasteRetryExhaustedMessage = "Einfügen fehlgeschlagen – Text ist in der Zwischenablage"
    private static let concealedPasteboardType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")

    /// Creates the workflow instance for a given type, or reports why it can't be built
    /// right now (#192) — `nil` only when the factory itself hasn't been wired up yet.
    /// Injected so tests can substitute lightweight fakes for the 5 real workflow types.
    typealias WorkflowFactory = (WorkflowType) -> WorkflowBuildResult?

    /// Performs the actual Cmd+V keystroke. Injected so tests can verify retry behavior
    /// without posting real CGEvents.
    typealias PasteAction = @MainActor () -> Void

    /// Returns whether accessibility automation is currently trusted, optionally prompting.
    typealias TrustCheck = @MainActor (_ promptIfNeeded: Bool) -> Bool

    /// Returns the frontmost application's process identifier, if any.
    typealias FrontmostPidProvider = @MainActor () -> pid_t?

    var activeWorkflow: (any Workflow)?
    /// Message text from the most recent `.error` phase, e.g. a known recording-start
    /// failure ("Kein Mikrofon verfügbar."). Read by `RecordingOverlayController` when
    /// it decides to surface a start error in the signal pill.
    private(set) var lastErrorMessage: String?
    /// Structured live-dictate transcript (#150/#151), updated throughout recording
    /// by the live path. Read by `RecordingOverlayController` while `.recording`.
    private(set) var lastLiveTranscriptDisplay: LiveTranscriptDisplay?
    /// Set when the live engine failed mid-dictation and rescued segments were pasted
    /// (ADR 0005). Read by `RecordingOverlayController` to enter `.bergungError`.
    private(set) var bergungMessage: String?
    /// Set when the paste retry window ran out without the target becoming frontmost
    /// (#176). Consumed by `RecordingOverlayController`, which surfaces the persistent
    /// pill error or bounces the Dock. Deliberately outlives the post-output workflow
    /// cleanup — the ~1.5s retry window ends after the 1.05s cleanup already ran.
    private(set) var pasteFailureMessage: String?
    /// Snapshot of `Workflow.processingLabel` (#128), captured while the workflow is still
    /// live so `RecordingOverlayController` can read it after the workflow resets.
    private(set) var lastProcessingLabel: String?
    /// Snapshot of `Workflow.completionLabel` (#128), captured right when the workflow's
    /// rewrite step finishes — before the ~1s post-output cleanup nils out `activeWorkflow`.
    private(set) var lastCompletionLabel: String?
    var menuBarStatus: MenuBarStatus = .idle {
        didSet {
            guard oldValue != menuBarStatus else { return }
            onMenuBarStatusChange?(menuBarStatus)
        }
    }
    var accessibilityPermissionGranted = false {
        didSet {
            guard oldValue != accessibilityPermissionGranted else { return }
            onAccessibilityPermissionChange?(accessibilityPermissionGranted)
        }
    }

    enum FinishReason: Equatable {
        /// A hotkey-background workflow errored out.
        case errorDuringBackgroundLaunch
        /// Output was just delivered (paste attempted); the workflow itself is still
        /// live until its post-output cleanup window elapses.
        case outputDelivered(source: WorkflowLaunchSource)
        /// The workflow finished its post-output cleanup window and was reset.
        case outputCleanup
    }

    var onPasteTargetActivationNeeded: ((PasteTarget) -> Void)?
    var onWorkflowOutput: ((String) -> Void)?
    var onWorkflowFinished: ((FinishReason) -> Void)?
    var onMenuBarStatusChange: ((MenuBarStatus) -> Void)?
    var onAccessibilityPermissionChange: ((Bool) -> Void)?
    /// Called before each paste attempt so the host can dismiss a visible popover, if any.
    var onWillPaste: (() -> Void)?

    /// `nil` means "not yet configured" — `start()` becomes a no-op until the host wires
    /// in the real factory. Avoids constructing this with a dummy always-nil closure.
    var workflowFactory: WorkflowFactory?
    private let pasteAction: PasteAction
    private let trustCheck: TrustCheck
    private let frontmostPidProvider: FrontmostPidProvider
    private let writeToPasteboard: (String) -> Void

    private(set) var activeLaunchSource: WorkflowLaunchSource = .manual
    private var activePasteTarget: PasteTarget?

    /// Process id of the app captured as the insertion target at workflow start, if any.
    /// Read by `RecordingOverlayController` to keep the text-cursor overlay bound to that
    /// specific app's caret even if focus moves to a different app or window meanwhile.
    var activePasteTargetProcessIdentifier: pid_t? { activePasteTarget?.processIdentifier }
    private var menuBarStatusResetTask: Task<Void, Never>?
    private var workflowCleanupTask: Task<Void, Never>?

    init(
        workflowFactory: WorkflowFactory? = nil,
        pasteAction: @escaping PasteAction = { WorkflowOrchestrator.defaultPasteAction() },
        trustCheck: @escaping TrustCheck = { AccessibilityPermissionService.isTrusted(promptIfNeeded: $0) },
        frontmostPidProvider: @escaping FrontmostPidProvider = { WorkflowOrchestrator.defaultFrontmostPidProvider() },
        writeToPasteboard: ((String) -> Void)? = nil
    ) {
        self.workflowFactory = workflowFactory
        self.pasteAction = pasteAction
        self.trustCheck = trustCheck
        self.frontmostPidProvider = frontmostPidProvider
        self.writeToPasteboard = writeToPasteboard ?? Self.defaultWriteToPasteboard
    }

    // MARK: - Workflow Lifecycle

    @discardableResult
    func start(
        _ type: WorkflowType,
        source: WorkflowLaunchSource,
        pasteTarget: PasteTarget?
    ) -> WorkflowStartOutcome {
        guard let buildResult = workflowFactory?(type) else { return .started }

        let workflow: any Workflow
        switch buildResult {
        case .workflow(let built):
            workflow = built
        case .rejected(let rejection):
            reportStartRejection(type, message: rejection.message)
            return .rejected(rejection)
        }

        activeWorkflow?.stop()
        menuBarStatusResetTask?.cancel()
        workflowCleanupTask?.cancel()
        activeLaunchSource = source
        activePasteTarget = pasteTarget
        lastLiveTranscriptDisplay = nil
        lastProcessingLabel = nil
        lastCompletionLabel = nil
        bergungMessage = nil
        pasteFailureMessage = nil

        workflow.onOutput = { [weak self, weak workflow] text in
            self?.handleWorkflowOutput(text, workflow: workflow)
        }
        workflow.onPhaseChange = { [weak self, weak workflow] phase in
            guard let self, let workflow else { return }
            self.handlePhaseChange(phase, workflow: workflow)
        }

        activeWorkflow = workflow
        workflow.start()
        return .started
    }

    func stop() {
        activeWorkflow?.stop()
    }

    func reset() {
        activeWorkflow?.reset()
        activeWorkflow = nil
        activePasteTarget = nil
        activeLaunchSource = .manual
        menuBarStatusResetTask?.cancel()
        workflowCleanupTask?.cancel()
        menuBarStatus = .idle
    }

    // MARK: - Output / Paste

    private func handleWorkflowOutput(_ text: String, workflow: (any Workflow)?) {
        pasteAtCursor(text, target: activePasteTarget, originatingWorkflow: workflow)
        onWorkflowOutput?(text)
        onWorkflowFinished?(.outputDelivered(source: activeLaunchSource))
        scheduleWorkflowCleanup(after: 1.05)
    }

    /// Copies the text, restores focus when needed, then simulates Cmd+V.
    /// The text intentionally remains on the clipboard as a fallback if paste is blocked.
    func pasteAtCursor(_ text: String, target: PasteTarget?, originatingWorkflow: (any Workflow)? = nil) {
        writeToPasteboard(text)
        onWillPaste?()

        pasteLogger.info(
            "Paste start: target \(target?.bundleIdentifier ?? "<none>", privacy: .public) (pid \(target?.processIdentifier ?? -1))"
        )

        let trusted = trustCheck(true)
        accessibilityPermissionGranted = trusted
        guard trusted else {
            pasteLogger.error("Paste aborted: accessibility trust check failed")
            menuBarStatus = .error(activeWorkflow?.type)
            return
        }

        attemptPasteTrusted(
            target: target,
            workflowType: activeWorkflow?.type,
            originatingWorkflowID: originatingWorkflow.map(ObjectIdentifier.init),
            fastAttemptsRemaining: Self.pasteRetryInitialAttempts,
            slowAttemptsRemaining: Self.pasteRetrySlowAttempts
        )
    }

    private func attemptPasteTrusted(
        target: PasteTarget?,
        workflowType: WorkflowType?,
        originatingWorkflowID: ObjectIdentifier?,
        fastAttemptsRemaining: Int,
        slowAttemptsRemaining: Int
    ) {
        guard let target else { return }

        let frontmostPid = frontmostPidProvider()
        if frontmostPid == target.processIdentifier {
            pasteLogger.info(
                "Paste: Cmd+V dispatched to \(target.bundleIdentifier ?? "<none>", privacy: .public) (pid \(target.processIdentifier))"
            )
            pasteAction()
            return
        }

        pasteLogger.debug(
            "Paste retry: target pid \(target.processIdentifier) not frontmost, requesting activation (fast \(fastAttemptsRemaining), slow \(slowAttemptsRemaining))"
        )
        onPasteTargetActivationNeeded?(target)

        guard let step = nextRetryStep(fastRemaining: fastAttemptsRemaining, slowRemaining: slowAttemptsRemaining) else {
            reportPasteRetryExhausted(
                target: target, workflowType: workflowType, originatingWorkflowID: originatingWorkflowID
            )
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + step.delay) { [weak self] in
            self?.attemptPasteTrusted(
                target: target,
                workflowType: workflowType,
                originatingWorkflowID: originatingWorkflowID,
                fastAttemptsRemaining: step.fastRemaining,
                slowAttemptsRemaining: step.slowRemaining
            )
        }
    }

    private func nextRetryStep(
        fastRemaining: Int,
        slowRemaining: Int
    ) -> (delay: TimeInterval, fastRemaining: Int, slowRemaining: Int)? {
        if fastRemaining > 0 {
            let delay: TimeInterval
            switch fastRemaining {
            case 16...:
                delay = 0.015
            case 8...15:
                delay = 0.025
            default:
                delay = 0.04
            }
            return (delay, fastRemaining - 1, slowRemaining)
        }
        if slowRemaining > 0 {
            return (Self.pasteRetrySlowInterval, 0, slowRemaining - 1)
        }
        return nil
    }

    private func reportPasteRetryExhausted(
        target: PasteTarget,
        workflowType: WorkflowType?,
        originatingWorkflowID: ObjectIdentifier?
    ) {
        // The ~1.5s retry window outlives the 1.05s post-output cleanup, so a `nil`
        // `activeWorkflow` is the normal, expected case here — but a *different* live
        // workflow means the user already started a new run; signaling then would show
        // a stale error for a workflow they have left behind (#176).
        if let originatingWorkflowID,
           let activeWorkflow,
           ObjectIdentifier(activeWorkflow) != originatingWorkflowID {
            pasteLogger.debug("Paste retry exhaustion ignored: a newer workflow replaced the originating one")
            return
        }
        pasteLogger.error(
            "Paste retry exhausted: \(target.bundleIdentifier ?? "<none>", privacy: .public) (pid \(target.processIdentifier)) never became frontmost; text stays on the clipboard"
        )
        pasteFailureMessage = Self.pasteRetryExhaustedMessage
        menuBarStatus = .error(workflowType)
    }

    /// Surfaces a workflow-start rejection (#190, fixes F1 from #188) through the same
    /// signal-pill error state an in-flight failure uses. No workflow is created here, so
    /// this path can never start audio capture — `RecordingOverlayController` can't tell a
    /// rejected start apart from a real one, which is the point: reuse the existing,
    /// auto-dismissing error state instead of inventing a new display state.
    func reportStartRejection(_ type: WorkflowType, message: String) {
        menuBarStatusResetTask?.cancel()
        lastErrorMessage = message
        menuBarStatus = .error(type)
        scheduleMenuBarStatusReset(after: 1.6)
    }

    /// Records a fresh structured live transcript from the streaming callback (#150/#151).
    func updateLiveTranscriptDisplay(_ display: LiveTranscriptDisplay) {
        lastLiveTranscriptDisplay = display
    }

    /// Records a partial transcript string, wrapping it as volatile-only display (#128 compat).
    func updatePartialTranscript(_ text: String) {
        lastLiveTranscriptDisplay = LiveTranscriptDisplay(volatileText: text)
    }

    /// Signals that the live engine failed and rescued segments were pasted (ADR 0005).
    func reportBergung(message: String?) {
        bergungMessage = message
    }

    /// Returns the pending paste-failure message exactly once, so the consumer can act
    /// on it without a second delivery on the next poll (#176).
    func takePasteFailureMessage() -> String? {
        defer { pasteFailureMessage = nil }
        return pasteFailureMessage
    }

    // MARK: - Phase Handling

    private func handlePhaseChange(_ phase: WorkflowPhase, workflow: any Workflow) {
        menuBarStatusResetTask?.cancel()

        switch phase {
        case .idle:
            if activeWorkflow == nil {
                menuBarStatus = .idle
            }

        case .running:
            menuBarStatus = workflow.isRecording
                ? .recording(workflow.type)
                : .processing(workflow.type)
            if !workflow.isRecording {
                lastProcessingLabel = workflow.processingLabel
            }

        case .done:
            menuBarStatus = .success(workflow.type)
            lastCompletionLabel = workflow.completionLabel

        case .error(let message):
            lastErrorMessage = message
            menuBarStatus = .error(workflow.type)
            if activeLaunchSource == .hotkeyBackground {
                activeWorkflow = nil
                activePasteTarget = nil
                onWorkflowFinished?(.errorDuringBackgroundLaunch)
            }
            scheduleMenuBarStatusReset(after: 1.6)
        }
    }

    private func scheduleWorkflowCleanup(after delay: TimeInterval) {
        guard let workflow = activeWorkflow else { return }

        workflowCleanupTask?.cancel()
        let workflowID = ObjectIdentifier(workflow)

        workflowCleanupTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, let activeWorkflow = self.activeWorkflow else { return }
            guard ObjectIdentifier(activeWorkflow) == workflowID else { return }

            activeWorkflow.reset()
            self.activeWorkflow = nil
            self.activePasteTarget = nil
            self.activeLaunchSource = .manual
            self.menuBarStatus = .idle
            self.onWorkflowFinished?(.outputCleanup)
        }
    }

    private func scheduleMenuBarStatusReset(after delay: TimeInterval) {
        menuBarStatusResetTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self else { return }
            if self.activeWorkflow == nil || !(self.activeWorkflow?.phase.isActive ?? false) {
                self.menuBarStatus = .idle
            }
        }
    }

    // MARK: - Defaults

    private static func defaultWriteToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.declareTypes([.string, concealedPasteboardType], owner: nil)
        pasteboard.setString(text, forType: .string)
        pasteboard.setString("", forType: concealedPasteboardType)
    }

    private static func defaultPasteAction() {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    private static func defaultFrontmostPidProvider() -> pid_t? {
        NSWorkspace.shared.frontmostApplication?.processIdentifier
    }
}

struct PasteTarget {
    let bundleIdentifier: String?
    let processIdentifier: pid_t
    let application: NSRunningApplication
}
