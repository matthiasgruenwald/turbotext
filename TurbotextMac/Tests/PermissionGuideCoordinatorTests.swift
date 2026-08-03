import XCTest
@testable import Turbotext

private final class FakeGuidePanel: PermissionGuidePanelShowing {
    private(set) var showCount = 0
    private(set) var hideCount = 0
    private(set) var repositionCount = 0

    func showGuide() { showCount += 1 }
    func hideGuide() { hideCount += 1 }
    func repositionGuide() { repositionCount += 1 }
}

private final class FakeScheduler {
    private(set) var scheduled: [(delay: TimeInterval, action: () -> Void)] = []

    func schedule(delay: TimeInterval, action: @escaping () -> Void) {
        scheduled.append((delay, action))
    }

    func runAll() {
        let pending = scheduled
        scheduled = []
        pending.forEach { $0.action() }
    }
}

@MainActor
final class PermissionGuideCoordinatorTests: XCTestCase {

    private final class PermissionState {
        var accessibility = false
        var inputMonitoring = false
    }

    private var permissions: PermissionState!
    private var openedURLs: [URL]!
    private var settingsVisible: Bool!
    private var activationCount: Int!
    private var panel: FakeGuidePanel!
    private var scheduler: FakeScheduler!
    private var statusRefreshCount: Int!

    override func setUp() {
        super.setUp()
        permissions = PermissionState()
        openedURLs = []
        settingsVisible = true
        activationCount = 0
        panel = FakeGuidePanel()
        scheduler = FakeScheduler()
        statusRefreshCount = 0
    }

    private func makeCoordinator(settingsVisibleOverride: Bool? = nil) -> PermissionGuideCoordinator {
        let coordinator = PermissionGuideCoordinator(
            openURL: { [unowned self] url in self.openedURLs.append(url) },
            isGranted: { [unowned self] step in
                switch step {
                case .accessibility: return self.permissions.accessibility
                case .inputMonitoring: return self.permissions.inputMonitoring
                }
            },
            settingsWindowFrame: { [unowned self] in settingsVisible == true ? CGRect(x: 0, y: 0, width: 770, height: 560) : nil },
            activateSystemSettings: { [unowned self] in self.activationCount += 1 },
            schedule: { [unowned self] delay, action in self.scheduler.schedule(delay: delay, action: action) }
        )
        coordinator.panel = panel
        coordinator.onPermissionStatusChanged = { [unowned self] in self.statusRefreshCount += 1 }
        return coordinator
    }

    // MARK: - start

    func testStartPlansBothStepsAndOpensFirstSettingsPane() {
        let coordinator = makeCoordinator()

        coordinator.start(requested: [.accessibility, .inputMonitoring])

        XCTAssertTrue(coordinator.isActive)
        XCTAssertEqual(coordinator.steps, [.accessibility, .inputMonitoring])
        XCTAssertEqual(coordinator.currentStep, .accessibility)
        XCTAssertEqual(openedURLs, [PermissionGuideStep.accessibility.settingsDeepLink])
        XCTAssertEqual(panel.showCount, 1)
    }

    func testStartSkipsGrantedSteps() {
        permissions.accessibility = true
        let coordinator = makeCoordinator()

        coordinator.start(requested: [.accessibility, .inputMonitoring])

        XCTAssertEqual(coordinator.steps, [.inputMonitoring])
        XCTAssertEqual(coordinator.currentStep, .inputMonitoring)
        XCTAssertEqual(openedURLs, [PermissionGuideStep.inputMonitoring.settingsDeepLink])
    }

    func testStartIsNoOpWhenEverythingGranted() {
        permissions.accessibility = true
        permissions.inputMonitoring = true
        let coordinator = makeCoordinator()

        coordinator.start(requested: [.accessibility, .inputMonitoring])

        XCTAssertFalse(coordinator.isActive)
        XCTAssertEqual(panel.showCount, 0)
        XCTAssertEqual(openedURLs, [])
        XCTAssertEqual(statusRefreshCount, 1)
    }

    func testStartWhileActiveIsIgnored() {
        let coordinator = makeCoordinator()
        coordinator.start(requested: [.accessibility, .inputMonitoring])

        coordinator.start(requested: [.inputMonitoring])

        XCTAssertEqual(coordinator.currentStep, .accessibility)
        XCTAssertEqual(openedURLs.count, 1)
    }

    func testStartSchedulesActivationRetries() {
        let coordinator = makeCoordinator()

        coordinator.start(requested: [.accessibility])

        XCTAssertEqual(scheduler.scheduled.map(\.delay), PermissionGuideCoordinator.activationRetryDelays)
        scheduler.runAll()
        XCTAssertEqual(activationCount, PermissionGuideCoordinator.activationRetryDelays.count)
    }

    // MARK: - tick

    func testTickAdvancesWhenFirstStepGranted() {
        let coordinator = makeCoordinator()
        coordinator.start(requested: [.accessibility, .inputMonitoring])
        openedURLs = []

        permissions.accessibility = true
        coordinator.tick()

        XCTAssertEqual(coordinator.currentStep, .inputMonitoring)
        XCTAssertEqual(coordinator.progressLabel, "2/2")
        XCTAssertEqual(openedURLs, [PermissionGuideStep.inputMonitoring.settingsDeepLink])
        XCTAssertEqual(statusRefreshCount, 1)
        XCTAssertTrue(coordinator.isActive)
    }

    func testTickCompletesFlowWhenLastStepGranted() {
        let coordinator = makeCoordinator()
        coordinator.start(requested: [.accessibility])

        permissions.accessibility = true
        coordinator.tick()

        XCTAssertFalse(coordinator.isActive)
        XCTAssertEqual(panel.hideCount, 1)
        XCTAssertEqual(statusRefreshCount, 1)
    }

    func testTickAbortsAfterThreeConsecutiveSettingsClosedTicks() {
        settingsVisible = false
        let coordinator = makeCoordinator()
        coordinator.start(requested: [.accessibility])

        exhaustGrace(coordinator)
        coordinator.tick()
        coordinator.tick()
        XCTAssertTrue(coordinator.isActive)
        coordinator.tick()

        XCTAssertFalse(coordinator.isActive)
        XCTAssertEqual(panel.hideCount, 1)
    }

    func testHiddenCounterResetsWhenSettingsReappear() {
        settingsVisible = false
        let coordinator = makeCoordinator()
        coordinator.start(requested: [.accessibility])
        exhaustGrace(coordinator)

        coordinator.tick()
        coordinator.tick()
        settingsVisible = true
        coordinator.tick()
        settingsVisible = false
        coordinator.tick()
        coordinator.tick()

        XCTAssertTrue(coordinator.isActive)
    }

    func testGraceTicksProtectAgainstSlowSettingsLaunch() {
        settingsVisible = false
        let coordinator = makeCoordinator()
        coordinator.start(requested: [.accessibility])

        coordinator.tick()
        coordinator.tick()
        coordinator.tick()

        XCTAssertTrue(coordinator.isActive)
        settingsVisible = true
        coordinator.tick()
        XCTAssertTrue(coordinator.isActive)
    }

    func testTickRepositionsPanelWhileSettingsVisible() {
        let coordinator = makeCoordinator()
        coordinator.start(requested: [.accessibility])
        let repositionsAfterStart = panel.repositionCount

        coordinator.tick()

        XCTAssertEqual(panel.repositionCount, repositionsAfterStart + 1)
    }

    // MARK: - skip / cancel

    func testSkipAdvancesFromInputMonitoringStep() {
        permissions.accessibility = true
        let coordinator = makeCoordinator()
        coordinator.start(requested: [.accessibility, .inputMonitoring])

        coordinator.skipCurrentStep()

        XCTAssertFalse(coordinator.isActive)
        XCTAssertEqual(panel.hideCount, 1)
    }

    func testSkipIsIgnoredOnAccessibilityStep() {
        let coordinator = makeCoordinator()
        coordinator.start(requested: [.accessibility, .inputMonitoring])

        coordinator.skipCurrentStep()

        XCTAssertTrue(coordinator.isActive)
        XCTAssertEqual(coordinator.currentStep, .accessibility)
    }

    func testCancelStopsFlowAndHidesPanel() {
        let coordinator = makeCoordinator()
        coordinator.start(requested: [.accessibility, .inputMonitoring])

        coordinator.cancel()

        XCTAssertFalse(coordinator.isActive)
        XCTAssertEqual(panel.hideCount, 1)

        permissions.accessibility = true
        coordinator.tick()
        XCTAssertEqual(statusRefreshCount, 0)
    }

    // MARK: - progress label

    func testProgressLabelShowsCurrentStepOutOfTotal() {
        let coordinator = makeCoordinator()
        coordinator.start(requested: [.accessibility, .inputMonitoring])

        XCTAssertEqual(coordinator.progressLabel, "1/2")
    }

    private func exhaustGrace(_ coordinator: PermissionGuideCoordinator) {
        for _ in 0..<PermissionGuideCoordinator.hiddenGraceTicks {
            coordinator.tick()
        }
    }
}
