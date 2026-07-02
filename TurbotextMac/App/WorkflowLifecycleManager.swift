import AppKit
import Observation

/// Owns the `WorkflowOrchestrator` plus the page-routing decisions around starting,
/// stopping, and resetting a workflow. `AppState` delegates here; this type does not
/// know about `AppState` directly so it can be unit-tested by injecting a workflow factory.
@Observable
@MainActor
final class WorkflowLifecycleManager {
    let orchestrator: WorkflowOrchestrator

    var activeWorkflow: (any Workflow)? {
        orchestrator.activeWorkflow
    }
    var menuBarStatus: MenuBarStatus {
        orchestrator.menuBarStatus
    }
    var currentPhase: WorkflowPhase {
        activeWorkflow?.phase ?? .idle
    }

    var onPageChangeNeeded: ((PopoverPage) -> Void)?
    var onMenuBarStatusChange: ((MenuBarStatus) -> Void)?
    var onAccessibilityPermissionChange: ((Bool) -> Void)?
    var onPasteTargetActivationNeeded: ((PasteTarget) -> Void)?
    var onWorkflowOutput: ((String) -> Void)?
    var onWillPaste: (() -> Void)?

    private var activeLaunchSource: WorkflowLaunchSource = .manual

    init(orchestrator: WorkflowOrchestrator) {
        self.orchestrator = orchestrator
        wireOrchestratorCallbacks()
    }

    convenience init(workflowFactory: @escaping WorkflowOrchestrator.WorkflowFactory) {
        self.init(orchestrator: WorkflowOrchestrator(workflowFactory: workflowFactory))
    }

    private func wireOrchestratorCallbacks() {
        orchestrator.onPasteTargetActivationNeeded = { [weak self] target in
            self?.onPasteTargetActivationNeeded?(target)
        }
        orchestrator.onWorkflowOutput = { [weak self] text in
            self?.handleWorkflowOutputDelivered()
            self?.onWorkflowOutput?(text)
        }
        orchestrator.onWorkflowFinished = { [weak self] reason in
            self?.handleWorkflowFinished(reason)
        }
        orchestrator.onMenuBarStatusChange = { [weak self] status in
            self?.onMenuBarStatusChange?(status)
        }
        orchestrator.onAccessibilityPermissionChange = { [weak self] granted in
            self?.onAccessibilityPermissionChange?(granted)
        }
        orchestrator.onWillPaste = { [weak self] in
            self?.onWillPaste?()
        }
    }

    var workflowFactory: WorkflowOrchestrator.WorkflowFactory {
        get { orchestrator.workflowFactory }
        set { orchestrator.workflowFactory = newValue }
    }

    func start(
        _ type: WorkflowType,
        source: WorkflowLaunchSource,
        isAvailable: Bool,
        backendOverride: TranscriptionBackend? = nil,
        pasteTarget: PasteTarget?
    ) {
        guard isAvailable else {
            if source == .manual {
                onPageChangeNeeded?(.settings)
            }
            return
        }

        activeLaunchSource = source
        orchestrator.start(
            type,
            source: source,
            backendOverride: backendOverride,
            pasteTarget: pasteTarget
        )

        onPageChangeNeeded?(source.presentsWorkflowPage ? .workflow : .main)
    }

    func stop() {
        orchestrator.stop()
    }

    func reset() {
        orchestrator.reset()
        activeLaunchSource = .manual
        onPageChangeNeeded?(.main)
    }

    private func handleWorkflowOutputDelivered() {
        if activeLaunchSource == .hotkeyBackground {
            onPageChangeNeeded?(.main)
        }
    }

    private func handleWorkflowFinished(_ reason: WorkflowOrchestrator.FinishReason) {
        switch reason {
        case .errorDuringBackgroundLaunch:
            onPageChangeNeeded?(.main)
        case .outputCleanup:
            activeLaunchSource = .manual
            onWorkflowFinishedCleanup?()
        }
    }

    /// Fired on `.outputCleanup` finish; the host decides whether to route to `.main`
    /// (it depends on `isPopoverShown`, which this manager does not own).
    var onWorkflowFinishedCleanup: (() -> Void)?
}
