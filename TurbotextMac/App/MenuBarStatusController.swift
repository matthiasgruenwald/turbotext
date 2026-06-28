import AppKit

enum MenuBarStatus: Equatable {
    case idle
    case recording(WorkflowType)
    case processing(WorkflowType)
    case success(WorkflowType?)
    case error(WorkflowType?)
}

/// Which cloud-mode marker the idle menu bar icon should show.
/// `.none` covers both secure-local mode and not-yet-configured states.
enum MenuBarCloudIndicator: Equatable {
    case none
    case groqReady
    case openAIFallback

    static func resolve(secureLocalModeEnabled: Bool, hasGroqKey: Bool, fallbackActive: Bool) -> MenuBarCloudIndicator {
        if secureLocalModeEnabled { return .none }
        if hasGroqKey && !fallbackActive { return .groqReady }
        return .openAIFallback
    }
}

/// Whether the menu bar icon should show a red X overlay for the current network status.
/// Only `.red` is a show-stopper; `.yellow` (degraded but working) doesn't warrant the alert.
enum MenuBarNetworkAlert {
    static func shouldShowRedX(for status: NetworkQualityStatus) -> Bool {
        status == .red
    }
}

/// Idle-state tooltip text. Missing permissions take precedence over quota info,
/// since they're the more urgent reason Turbotext might not work as expected.
enum MenuBarIdleTooltip {
    static func text(
        accessibilityGranted: Bool,
        inputMonitoringGranted: Bool,
        cloudIndicator: MenuBarCloudIndicator,
        groqQuotaUsedToday: String?
    ) -> String {
        var missing: [String] = []
        if !accessibilityGranted { missing.append("Bedienungshilfen fehlen") }
        if !inputMonitoringGranted { missing.append("Tastaturüberwachung fehlt") }

        guard missing.isEmpty else {
            return "Turbotext eingeschränkt: \(missing.joined(separator: ", "))"
        }

        guard cloudIndicator == .groqReady, let groqQuotaUsedToday else {
            return "Turbotext ist bereit"
        }
        return "Turbotext ist bereit · heute \(groqQuotaUsedToday) Groq-Kontingent genutzt"
    }
}

@MainActor
final class MenuBarStatusController {
    private weak var button: NSStatusBarButton?
    private var animationTimer: Timer?
    private var animationFrame = 0
    private var currentStatus: MenuBarStatus = .idle

    private var cloudIndicator: MenuBarCloudIndicator = .none
    private var accessibilityGranted = false
    private var inputMonitoringGranted = false
    private var networkStatus: NetworkQualityStatus = .green

    func attach(to button: NSStatusBarButton) {
        self.button = button
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        renderCurrentStatus()
    }

    func update(to status: MenuBarStatus) {
        currentStatus = status
        animationFrame = 0
        configureAnimationIfNeeded()
        renderCurrentStatus()
    }

    func setCloudIndicator(_ indicator: MenuBarCloudIndicator) {
        guard cloudIndicator != indicator else { return }
        cloudIndicator = indicator
        renderCurrentStatus()
    }

    func setNetworkStatus(_ status: NetworkQualityStatus) {
        guard networkStatus != status else { return }
        networkStatus = status
        renderCurrentStatus()
    }

    func setPermissions(accessibilityGranted: Bool, inputMonitoringGranted: Bool) {
        guard self.accessibilityGranted != accessibilityGranted
            || self.inputMonitoringGranted != inputMonitoringGranted else { return }
        self.accessibilityGranted = accessibilityGranted
        self.inputMonitoringGranted = inputMonitoringGranted
        renderCurrentStatus()
    }

    private func configureAnimationIfNeeded() {
        stopAnimation()

        switch currentStatus {
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
        animationFrame = (animationFrame + 1) % 4
        renderCurrentStatus()
    }

    private func renderCurrentStatus() {
        guard let button else { return }
        button.image = MenuBarStatusIconRenderer.makeImage(
            for: currentStatus,
            frame: animationFrame,
            cloudIndicator: cloudIndicator,
            showNetworkAlert: MenuBarNetworkAlert.shouldShowRedX(for: networkStatus)
        )
        button.image?.isTemplate = true
        button.toolTip = tooltip(for: currentStatus)
    }

    private func tooltip(for status: MenuBarStatus) -> String {
        switch status {
        case .idle:
            return MenuBarIdleTooltip.text(
                accessibilityGranted: accessibilityGranted,
                inputMonitoringGranted: inputMonitoringGranted,
                cloudIndicator: cloudIndicator,
                groqQuotaUsedToday: GroqQuotaStore.shared.formattedUsedToday
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

    deinit {
        animationTimer?.invalidate()
    }
}
