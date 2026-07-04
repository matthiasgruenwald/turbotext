import XCTest
@testable import Turbotext

@MainActor
final class MenuBarFacadeTests: XCTestCase {

    private func makeProvider() -> GroqTranscriptionProvider {
        GroqTranscriptionProvider(
            quotaManager: GroqQuotaManager(defaults: InMemoryPersistence()),
            fallbackManager: GroqFallbackManager(defaults: InMemoryPersistence())
        )
    }

    func testExposesInjectedWorkflowStatusAndPermissions() {
        var startedType: WorkflowType?
        var stopCalled = false

        let facade = MenuBarFacade(
            workflowStatus: .recording(.transcription),
            quotaUIStatus: GroqQuotaUIStatus(formattedUsedToday: "5 Min.", fallbackActive: true, rateLimitResetAt: nil),
            accessibilityPermissionGranted: true,
            inputMonitoringPermissionGranted: false,
            startWorkflow: { type in startedType = type },
            stopWorkflow: { stopCalled = true }
        )

        XCTAssertEqual(facade.workflowStatus, .recording(.transcription))
        XCTAssertEqual(facade.quotaUIStatus.formattedUsedToday, "5 Min.")
        XCTAssertTrue(facade.quotaUIStatus.fallbackActive)
        XCTAssertTrue(facade.accessibilityPermissionGranted)
        XCTAssertFalse(facade.inputMonitoringPermissionGranted)

        facade.startWorkflow(.transcription)
        XCTAssertEqual(startedType, .transcription)

        facade.stopWorkflow()
        XCTAssertTrue(stopCalled)
    }

    func testAppStateExposesFacadeReflectingCurrentState() {
        let appState = AppState(groqTranscriptionProvider: makeProvider())

        let facade = appState.menuBarFacade

        XCTAssertEqual(facade.workflowStatus, appState.workflowLifecycle.orchestrator.menuBarStatus)
        XCTAssertEqual(facade.quotaUIStatus, appState.groqTranscriptionProvider.quotaUIStatus)
        XCTAssertEqual(facade.accessibilityPermissionGranted, appState.accessibilityPermissionGranted)
        XCTAssertEqual(facade.inputMonitoringPermissionGranted, appState.inputMonitoringPermissionGranted)
    }

    func testAppStateFacadeStopWorkflowDelegatesToLifecycle() {
        let appState = AppState(groqTranscriptionProvider: makeProvider())

        // No active workflow: stop() should simply be a no-op that doesn't crash.
        appState.menuBarFacade.stopWorkflow()

        XCTAssertNil(appState.activeWorkflow)
    }
}
