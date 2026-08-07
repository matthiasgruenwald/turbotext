import XCTest
@testable import Turbotext

/// Covers the AppState-level wiring of the start gate (#190, fixes F1 from #188): a
/// missing access configuration must reject the start with a named reason instead of
/// ending silently, on the hotkey-background path in particular. The Apple Speech
/// readiness branch isn't covered here since `AppState` constructs the real
/// `AppleSpeechAvailability` without a test seam — its readiness reflects whatever this
/// machine actually reports.
@MainActor
final class WorkflowStartRejectionTests: XCTestCase {

    override func tearDown() {
        KeychainService.delete(key: .openAIAPIKey)
        super.tearDown()
    }

    func testStartWorkflowReportsRejectionWhenAccessNotConfigured() {
        KeychainService.delete(key: .openAIAPIKey)
        let appState = AppState()
        appState.appSettings.alwaysLocalTranscription = false

        appState.startWorkflow(.transcription, source: .hotkeyBackground)

        XCTAssertNil(appState.activeWorkflow)
        XCTAssertEqual(appState.workflowLifecycle.orchestrator.menuBarStatus, .error(.transcription))
        XCTAssertNotNil(appState.workflowLifecycle.orchestrator.lastErrorMessage)
    }

    /// Configured access alone must clear the rejection — doesn't assert the workflow
    /// actually starts (that would open a real microphone / hit the network), only that
    /// this specific veto is gone. `isWorkflowAvailable` already covers this predicate
    /// for the pre-existing UI-graying path.
    func testIsWorkflowAvailableReflectsAccessConfiguration() throws {
        try KeychainService.save(key: .openAIAPIKey, value: "sk-test-key-1234567890")
        let appState = AppState()
        appState.appSettings.alwaysLocalTranscription = false

        XCTAssertTrue(appState.isWorkflowAvailable(.textImprover))
    }
}
