/// Watches `AppSettings.dockModeEnabled` changes and applies `DockModeService` (ADR-0004).
/// Wired by `AppDelegate`, not `AppState`, so `AppState` no longer orchestrates this side effect.
@MainActor
final class DockModeObserver {
    private let apply: (Bool) -> Void

    init(apply: @escaping (Bool) -> Void) {
        self.apply = apply
    }

    func handleSettingsChange(old: AppSettings, new: AppSettings) {
        guard old.dockModeEnabled != new.dockModeEnabled else { return }
        apply(new.dockModeEnabled)
    }
}
