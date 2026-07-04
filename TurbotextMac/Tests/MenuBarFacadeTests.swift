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

    func testExposesInjectedPermissions() {
        let facade = MenuBarFacade(
            quotaUIStatus: GroqQuotaUIStatus(formattedUsedToday: "5 Min.", fallbackActive: true, rateLimitResetAt: nil),
            accessibilityPermissionGranted: true,
            inputMonitoringPermissionGranted: false
        )

        XCTAssertEqual(facade.quotaUIStatus.formattedUsedToday, "5 Min.")
        XCTAssertTrue(facade.quotaUIStatus.fallbackActive)
        XCTAssertTrue(facade.accessibilityPermissionGranted)
        XCTAssertFalse(facade.inputMonitoringPermissionGranted)
    }

    func testAppStateExposesFacadeReflectingCurrentState() {
        let appState = AppState(groqTranscriptionProvider: makeProvider())

        let facade = appState.menuBarFacade

        XCTAssertEqual(facade.quotaUIStatus, appState.groqTranscriptionProvider.quotaUIStatus)
        XCTAssertEqual(facade.accessibilityPermissionGranted, appState.accessibilityPermissionGranted)
        XCTAssertEqual(facade.inputMonitoringPermissionGranted, appState.inputMonitoringPermissionGranted)
    }
}
