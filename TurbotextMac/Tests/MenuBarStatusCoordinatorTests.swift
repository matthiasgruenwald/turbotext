import XCTest
@testable import Turbotext

@MainActor
final class MenuBarStatusCoordinatorTests: XCTestCase {

    private func makeProvider() -> GroqTranscriptionProvider {
        GroqTranscriptionProvider(
            quotaManager: GroqQuotaManager(defaults: InMemoryPersistence()),
            fallbackManager: GroqFallbackManager(defaults: InMemoryPersistence())
        )
    }

    func testInitialRenderStateReflectsInjectedSources() {
        let orchestrator = WorkflowOrchestrator()
        let networkPingService = NetworkPingService()
        let coordinator = MenuBarStatusCoordinator(
            orchestrator: orchestrator,
            groqTranscriptionProvider: makeProvider(),
            networkPingService: networkPingService,
            cloudIndicatorProvider: { .groqReady },
            groqQuotaUsedTodayProvider: { "5 min" }
        )

        XCTAssertEqual(coordinator.renderState.status, .idle)
        XCTAssertEqual(coordinator.renderState.cloudIndicator, .groqReady)
        XCTAssertEqual(coordinator.renderState.networkStatus, .red)
        XCTAssertFalse(coordinator.renderState.accessibilityGranted)
        XCTAssertFalse(coordinator.renderState.inputMonitoringGranted)
    }

    func testWorkflowStatusChangeUpdatesRenderState() {
        let orchestrator = WorkflowOrchestrator()
        let coordinator = MenuBarStatusCoordinator(
            orchestrator: orchestrator,
            groqTranscriptionProvider: makeProvider(),
            networkPingService: NetworkPingService(),
            cloudIndicatorProvider: { .none },
            groqQuotaUsedTodayProvider: { nil }
        )

        orchestrator.menuBarStatus = .recording(.transcription)

        XCTAssertEqual(coordinator.renderState.status, .recording(.transcription))
    }

    func testNetworkStatusChangeUpdatesRenderState() {
        let networkPingService = NetworkPingService()
        let coordinator = MenuBarStatusCoordinator(
            orchestrator: WorkflowOrchestrator(),
            groqTranscriptionProvider: makeProvider(),
            networkPingService: networkPingService,
            cloudIndicatorProvider: { .none },
            groqQuotaUsedTodayProvider: { nil }
        )

        networkPingService.onStatusChanged?(.red)

        XCTAssertEqual(coordinator.renderState.networkStatus, .red)
        XCTAssertTrue(coordinator.renderState.showNetworkAlert)
    }

    func testFallbackStateChangeRefreshesCloudIndicatorFromProvider() {
        let groqTranscriptionProvider = makeProvider()
        var indicator: MenuBarCloudIndicator = .groqReady
        let coordinator = MenuBarStatusCoordinator(
            orchestrator: WorkflowOrchestrator(),
            groqTranscriptionProvider: groqTranscriptionProvider,
            networkPingService: NetworkPingService(),
            cloudIndicatorProvider: { indicator },
            groqQuotaUsedTodayProvider: { nil }
        )
        XCTAssertEqual(coordinator.renderState.cloudIndicator, .groqReady)

        indicator = .openAIFallback
        groqTranscriptionProvider.onFallbackStateChanged?(true)

        XCTAssertEqual(coordinator.renderState.cloudIndicator, .openAIFallback)
    }

    func testUpdatePermissionsRefreshesRenderState() {
        let coordinator = MenuBarStatusCoordinator(
            orchestrator: WorkflowOrchestrator(),
            groqTranscriptionProvider: makeProvider(),
            networkPingService: NetworkPingService(),
            cloudIndicatorProvider: { .none },
            groqQuotaUsedTodayProvider: { nil }
        )

        coordinator.updatePermissions(accessibilityGranted: true, inputMonitoringGranted: false)

        XCTAssertTrue(coordinator.renderState.accessibilityGranted)
        XCTAssertFalse(coordinator.renderState.inputMonitoringGranted)
    }

    func testRefreshCloudIndicatorPullsLatestFromProvider() {
        var indicator: MenuBarCloudIndicator = .none
        let coordinator = MenuBarStatusCoordinator(
            orchestrator: WorkflowOrchestrator(),
            groqTranscriptionProvider: makeProvider(),
            networkPingService: NetworkPingService(),
            cloudIndicatorProvider: { indicator },
            groqQuotaUsedTodayProvider: { nil }
        )
        XCTAssertEqual(coordinator.renderState.cloudIndicator, .none)

        indicator = .groqReady
        coordinator.refreshCloudIndicator()

        XCTAssertEqual(coordinator.renderState.cloudIndicator, .groqReady)
    }

    func testTooltipUsesIdleTooltipLogic() {
        let coordinator = MenuBarStatusCoordinator(
            orchestrator: WorkflowOrchestrator(),
            groqTranscriptionProvider: makeProvider(),
            networkPingService: NetworkPingService(),
            cloudIndicatorProvider: { .groqReady },
            groqQuotaUsedTodayProvider: { "45 Min." }
        )
        coordinator.updatePermissions(accessibilityGranted: true, inputMonitoringGranted: true)

        XCTAssertEqual(coordinator.renderState.tooltip, "Turbotext ist bereit · heute 45 Min. Groq-Kontingent genutzt")
    }
}
