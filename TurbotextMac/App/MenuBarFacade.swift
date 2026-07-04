/// Narrow read-only surface for the menu bar status UI. `AppState` owns the full
/// subsystem graph (settings, workflows, quota/fallback, microphone, local models, hotkeys,
/// shortcuts, network) internally, but menu bar status consumers (e.g. `AppDelegate`'s
/// `MenuBarStatusCoordinator` wiring) only need Groq quota/fallback UI status and permission
/// status. Depending on this facade instead of `AppState` directly keeps that dependency
/// narrow and gives `AppState` a seam it can be tested through.
struct MenuBarFacade {
    let quotaUIStatus: GroqQuotaUIStatus
    let accessibilityPermissionGranted: Bool
    let inputMonitoringPermissionGranted: Bool
}
