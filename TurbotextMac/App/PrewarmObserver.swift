/// Watches `AppSettings` changes and triggers local-model prewarm.
/// Wired by `AppDelegate`, not `AppState`, so `AppState` no longer orchestrates this side effect.
@MainActor
final class PrewarmObserver {
    private let prewarm: () -> Void

    init(prewarm: @escaping () -> Void) {
        self.prewarm = prewarm
    }

    func handleSettingsChange(old: AppSettings, new: AppSettings) {
        prewarm()
    }
}
