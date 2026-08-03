import AppKit
import Observation

@MainActor
protocol PermissionGuidePanelShowing: AnyObject {
    func showGuide()
    func hideGuide()
    func repositionGuide()
}

/// State machine of the interactive permission onboarding (#156): opens System
/// Settings at the right pane, floats the guide panel next to it, polls TCC
/// status, advances through the steps and aborts when System Settings is closed.
@Observable
@MainActor
final class PermissionGuideCoordinator {
    static let pollInterval: TimeInterval = 0.9
    static let activationRetryDelays: [TimeInterval] = [0.25, 0.85, 1.45]
    // System Settings can take a few seconds to launch after the deep link;
    // counting "settings closed" immediately would abort a perfectly healthy flow.
    static let hiddenGraceTicks = 4

    private(set) var isActive = false
    private(set) var steps: [PermissionGuideStep] = []
    private(set) var currentStepIndex = 0
    private(set) var consecutiveSettingsClosed = 0

    weak var panel: PermissionGuidePanelShowing?
    var onPermissionStatusChanged: (() -> Void)?

    private let openURL: (URL) -> Void
    private let isGranted: @MainActor (PermissionGuideStep) -> Bool
    private let settingsWindowFrame: () -> CGRect?
    private let activateSystemSettings: () -> Void
    private let schedule: (TimeInterval, @escaping () -> Void) -> Void
    private var pollTimer: Timer?
    private var remainingGraceTicks = 0

    var currentStep: PermissionGuideStep? {
        steps.indices.contains(currentStepIndex) ? steps[currentStepIndex] : nil
    }

    var canSkipCurrentStep: Bool {
        isActive && currentStep == .inputMonitoring
    }

    var progressLabel: String {
        "\(currentStepIndex + 1)/\(steps.count)"
    }

    init(
        openURL: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) },
        isGranted: @escaping @MainActor (PermissionGuideStep) -> Bool = { $0.isGranted },
        settingsWindowFrame: @escaping () -> CGRect? = { SystemSettingsWindowFinder.currentFrame() },
        activateSystemSettings: @escaping () -> Void = { PermissionGuideSystemSettingsActivator.activate() },
        schedule: @escaping (TimeInterval, @escaping () -> Void) -> Void = { delay, action in
            let timer = Timer(timeInterval: delay, repeats: false) { _ in action() }
            RunLoop.main.add(timer, forMode: .common)
        }
    ) {
        self.openURL = openURL
        self.isGranted = isGranted
        self.settingsWindowFrame = settingsWindowFrame
        self.activateSystemSettings = activateSystemSettings
        self.schedule = schedule
    }

    func start(requested: Set<PermissionGuideStep>) {
        guard !isActive else { return }
        steps = PermissionGuidePlanner.planSteps(
            requested: requested,
            accessibilityGranted: isGranted(.accessibility),
            inputMonitoringGranted: isGranted(.inputMonitoring)
        )
        guard !steps.isEmpty else {
            onPermissionStatusChanged?()
            return
        }
        currentStepIndex = 0
        isActive = true
        beginStep(at: 0)
        startPolling()
    }

    func tick() {
        guard isActive, let step = currentStep else { return }
        switch PermissionGuideMonitor.evaluate(
            permissionGranted: isGranted(step),
            settingsVisible: settingsWindowFrame() != nil
        ) {
        case .permissionGranted:
            onPermissionStatusChanged?()
            advance()
        case .keepWatching:
            consecutiveSettingsClosed = 0
            panel?.repositionGuide()
        case .settingsClosed:
            guard remainingGraceTicks <= 0 else {
                remainingGraceTicks -= 1
                return
            }
            consecutiveSettingsClosed += 1
            if PermissionGuideMonitor.shouldAbort(consecutiveSettingsClosed: consecutiveSettingsClosed) {
                cancel()
            }
        }
    }

    func skipCurrentStep() {
        guard canSkipCurrentStep else { return }
        advance()
    }

    func cancel() {
        stopPolling()
        isActive = false
        steps = []
        currentStepIndex = 0
        consecutiveSettingsClosed = 0
        remainingGraceTicks = 0
        panel?.hideGuide()
    }

    private func beginStep(at index: Int) {
        guard let step = currentStep else { return }
        consecutiveSettingsClosed = 0
        remainingGraceTicks = Self.hiddenGraceTicks
        openURL(step.settingsDeepLink)
        panel?.showGuide()
        panel?.repositionGuide()
        Self.activationRetryDelays.forEach { delay in
            schedule(delay) { [weak self] in
                guard let self, self.isActive, self.currentStepIndex == index else { return }
                self.activateSystemSettings()
            }
        }
    }

    private func advance() {
        let next = currentStepIndex + 1
        if next < steps.count {
            currentStepIndex = next
            beginStep(at: next)
        } else {
            finish()
        }
    }

    private func finish() {
        stopPolling()
        isActive = false
        panel?.hideGuide()
    }

    private func startPolling() {
        stopPolling()
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }
}

enum PermissionGuideSystemSettingsActivator {
    static func activate() {
        NSRunningApplication
            .runningApplications(withBundleIdentifier: SystemSettingsWindowFinder.settingsBundleIdentifier)
            .first?
            .activate()
    }
}
