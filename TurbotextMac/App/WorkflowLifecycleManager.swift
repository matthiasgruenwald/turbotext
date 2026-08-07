import AppKit
import Observation
import OSLog

private let lifecycleLogger = Logger(subsystem: "app.turbotext.mac", category: "WorkflowLifecycle")

/// A named, user-visible reason a workflow start was refused (#190, fixes F1 from #188) —
/// replaces the previous silent no-op on the hotkey path. `reason` is a short, non-content
/// category for the diagnostics log line; `message` is what the recording overlay shows.
struct WorkflowStartRejection: Equatable {
    let reason: String
    let message: String
    /// Whether pressing the shortcut again right now has a realistic chance of succeeding
    /// (e.g. assets are installing) as opposed to needing the user to change something
    /// first (e.g. configure access, upgrade macOS).
    let canRetryImmediately: Bool
}

/// What a workflow start actually did (#190) — callers used to get nothing back and
/// couldn't distinguish "started" from "silently vetoed".
enum WorkflowStartOutcome: Equatable {
    case started
    case rejected(WorkflowStartRejection)
}

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

    /// Cheap pre-flight checks (#190) run before even asking `WorkflowFactory` to build
    /// anything: `.localTranscription`'s installed-model check and the remote-access
    /// configuration check. Sprachasset-Bereitschaft for the four cloud-capable types is
    /// *not* checked here since #192 — that's `resolveTranscriber`'s job, applied once
    /// inside `WorkflowFactory.build` regardless of live/file routing. `nil` means "go
    /// ahead". Defaults to always-allow so callers/tests that don't care about rejection
    /// keep working unmodified.
    var startGate: (WorkflowType) -> WorkflowStartRejection? = { _ in nil }

    @discardableResult
    func start(
        _ type: WorkflowType,
        source: WorkflowLaunchSource,
        backendOverride: TranscriptionBackend? = nil,
        pasteTarget: PasteTarget?
    ) -> WorkflowStartOutcome {
        if let rejection = startGate(type) {
            orchestrator.reportStartRejection(type, message: rejection.message)
            return handleRejection(rejection, type: type, source: source)
        }

        let outcome = orchestrator.start(
            type,
            source: source,
            backendOverride: backendOverride,
            pasteTarget: pasteTarget
        )

        switch outcome {
        case .started:
            onPageChangeNeeded?(source.presentsWorkflowPage ? .workflow : .main)
            return .started
        case .rejected(let rejection):
            return handleRejection(rejection, type: type, source: source)
        }
    }

    /// Shared tail for both rejection sources (the pre-flight `startGate` and, since
    /// #192, `WorkflowFactory`'s own transcriber-unavailable rejection surfaced through
    /// `orchestrator.start`): log it once, route manual launches to Settings, leave
    /// hotkey-background launches wherever they were.
    private func handleRejection(
        _ rejection: WorkflowStartRejection,
        type: WorkflowType,
        source: WorkflowLaunchSource
    ) -> WorkflowStartOutcome {
        lifecycleLogger.info(
            "Workflow start rejected: type=\(type.rawValue, privacy: .public) reason=\(rejection.reason, privacy: .public) source=\(String(describing: source), privacy: .public)"
        )
        if source == .manual {
            onPageChangeNeeded?(.settings)
        }
        return .rejected(rejection)
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
