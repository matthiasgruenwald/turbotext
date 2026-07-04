/// Narrow read-only + action surface for the menu bar status UI. `AppState` owns the full
/// subsystem graph (settings, workflows, quota/fallback, microphone, local models, hotkeys,
/// shortcuts, network) internally, but menu bar status consumers (e.g. `AppDelegate`'s
/// `MenuBarStatusCoordinator` wiring) only need workflow status, Groq quota/fallback UI status,
/// permission status, and start/stop actions. Depending on this facade instead of `AppState`
/// directly keeps that dependency narrow and gives `AppState` a seam it can be tested through.
struct MenuBarFacade {
    let workflowStatus: MenuBarStatus
    let quotaUIStatus: GroqQuotaUIStatus
    let accessibilityPermissionGranted: Bool
    let inputMonitoringPermissionGranted: Bool
    let startWorkflow: (WorkflowType) -> Void
    let stopWorkflow: () -> Void
}
