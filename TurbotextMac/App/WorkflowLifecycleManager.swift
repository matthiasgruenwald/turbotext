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
    var currentPhase: WorkflowPhase {
        activeWorkflow?.phase ?? .idle
    }

    var onPageChangeNeeded: ((PopoverPage) -> Void)?
    var onWillPaste: (() -> Void)?

    /// Reports whether the popover is currently shown, so `.outputCleanup` can decide
    /// whether it's safe to route back to `.main`. Defaults to `false` (never shown)
    /// until the host wires this up.
    var isPopoverShown: () -> Bool = { false }

    init(orchestrator: WorkflowOrchestrator, isPopoverShown: @escaping () -> Bool = { false }) {
        self.orchestrator = orchestrator
        self.isPopoverShown = isPopoverShown
        wireOrchestratorCallbacks()
    }

    convenience init(
        workflowFactory: WorkflowOrchestrator.WorkflowFactory? = nil,
        isPopoverShown: @escaping () -> Bool = { false }
    ) {
        self.init(orchestrator: WorkflowOrchestrator(workflowFactory: workflowFactory), isPopoverShown: isPopoverShown)
    }

    private func wireOrchestratorCallbacks() {
        orchestrator.onWorkflowFinished = { [weak self] reason in
            self?.handleWorkflowFinished(reason)
        }
        orchestrator.onWillPaste = { [weak self] in
            self?.onWillPaste?()
        }
    }

    var workflowFactory: WorkflowOrchestrator.WorkflowFactory? {
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
        onPageChangeNeeded?(.main)
    }

    private func handleWorkflowFinished(_ reason: WorkflowOrchestrator.FinishReason) {
        switch reason {
        case .errorDuringBackgroundLaunch:
            onPageChangeNeeded?(.main)
        case .outputDelivered(let source):
            if source == .hotkeyBackground {
                onPageChangeNeeded?(.main)
            }
        case .outputCleanup:
            guard !isPopoverShown() else { return }
            onPageChangeNeeded?(.main)
        }
    }
}
