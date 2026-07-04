import AppKit
import Observation

/// Everything `MenuBarStatusIconRenderer` and the status-bar tooltip need to render a frame.
struct MenuBarRenderState: Equatable {
    var status: MenuBarStatus = .idle
    var animationFrame = 0
    var cloudIndicator: MenuBarCloudIndicator = .none
    var networkStatus: NetworkQualityStatus = .red
    var accessibilityGranted = false
    var inputMonitoringGranted = false
    var groqQuotaUsedToday: String?

    var showNetworkAlert: Bool {
        MenuBarNetworkAlert.shouldShowRedX(for: networkStatus)
    }

    var tooltip: String {
        switch status {
        case .idle:
            return MenuBarIdleTooltip.text(
                accessibilityGranted: accessibilityGranted,
                inputMonitoringGranted: inputMonitoringGranted,
                cloudIndicator: cloudIndicator,
                groqQuotaUsedToday: groqQuotaUsedToday
            )
        case .recording(let type):
            return "\(type.displayName): Aufnahme läuft"
        case .processing(let type):
            return "\(type.displayName): Verarbeitung läuft"
        case .success(let type):
            if let type {
                return "\(type.displayName): Fertig"
            }
            return "Turbotext: Fertig"
        case .error(let type):
            if let type {
                return "\(type.displayName): Fehler"
            }
            return "Turbotext: Fehler"
        }
    }
}

/// Consolidates every source that can change the menu bar icon — workflow status, Groq
/// fallback/quota, network quality, and permissions — into a single `renderState`.
/// Replaces the previous 3 independently-wired callback chains (`quotaManager`/
/// `fallbackManager`, `networkPingService`, `appState.onCloudIndicatorRefreshNeeded`).
/// Groq state now comes from `GroqTranscriptionProvider.onFallbackStateChanged`.
@Observable
@MainActor
final class MenuBarStatusCoordinator {
    private(set) var renderState = MenuBarRenderState() {
        didSet { render() }
    }

    private weak var button: NSStatusBarButton?
    private var animationTimer: Timer?
    private let cloudIndicatorProvider: () -> MenuBarCloudIndicator
    private let groqQuotaUsedTodayProvider: () -> String?

    init(
        orchestrator: WorkflowOrchestrator,
        groqTranscriptionProvider: GroqTranscriptionProvider,
        networkPingService: NetworkPingService,
        cloudIndicatorProvider: @escaping () -> MenuBarCloudIndicator,
        groqQuotaUsedTodayProvider: @escaping () -> String?
    ) {
        self.cloudIndicatorProvider = cloudIndicatorProvider
        self.groqQuotaUsedTodayProvider = groqQuotaUsedTodayProvider

        renderState.status = orchestrator.menuBarStatus
        renderState.networkStatus = networkPingService.status
        renderState.cloudIndicator = cloudIndicatorProvider()
        renderState.groqQuotaUsedToday = groqQuotaUsedTodayProvider()

        orchestrator.onMenuBarStatusChange = { [weak self] status in
            self?.updateStatus(status)
        }
        groqTranscriptionProvider.onFallbackStateChanged = { [weak self] _ in
            self?.refreshCloudIndicator()
        }
        networkPingService.onStatusChanged = { [weak self] status in
            self?.updateNetworkStatus(status)
        }
    }

    func attach(to button: NSStatusBarButton) {
        self.button = button
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        render()
    }

    /// Call after anything that can change the cloud indicator (permissions, settings,
    /// page navigation, workflow output) — mirrors the old `onCloudIndicatorRefreshNeeded`.
    func refreshCloudIndicator() {
        renderState.cloudIndicator = cloudIndicatorProvider()
        renderState.groqQuotaUsedToday = groqQuotaUsedTodayProvider()
    }

    func updatePermissions(accessibilityGranted: Bool, inputMonitoringGranted: Bool) {
        renderState.accessibilityGranted = accessibilityGranted
        renderState.inputMonitoringGranted = inputMonitoringGranted
    }

    private func updateStatus(_ status: MenuBarStatus) {
        renderState.status = status
        renderState.animationFrame = 0
        configureAnimationIfNeeded(for: status)
    }

    private func updateNetworkStatus(_ status: NetworkQualityStatus) {
        renderState.networkStatus = status
    }

    private func configureAnimationIfNeeded(for status: MenuBarStatus) {
        stopAnimation()
        switch status {
        case .recording:
            startAnimation(interval: 0.12)
        case .processing:
            startAnimation(interval: 0.18)
        default:
            break
        }
    }

    private func startAnimation(interval: TimeInterval) {
        animationTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
        RunLoop.main.add(animationTimer!, forMode: .common)
    }

    private func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
    }

    private func tick() {
        renderState.animationFrame = (renderState.animationFrame + 1) % 4
    }

    private func render() {
        guard let button else { return }
        button.image = MenuBarStatusIconRenderer.makeImage(
            for: renderState.status,
            frame: renderState.animationFrame,
            cloudIndicator: renderState.cloudIndicator,
            showNetworkAlert: renderState.showNetworkAlert
        )
        button.image?.isTemplate = true
        button.toolTip = renderState.tooltip
    }

}
