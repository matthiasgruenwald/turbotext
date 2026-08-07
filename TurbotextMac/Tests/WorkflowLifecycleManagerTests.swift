import XCTest
import AppKit
@testable import Turbotext

@MainActor
@Observable
private final class FakeLifecycleWorkflow: Workflow {
    let type: WorkflowType
    var phase: WorkflowPhase = .idle {
        didSet { onPhaseChange?(phase) }
    }
    var onOutput: WorkflowOutputHandler?
    var onPhaseChange: WorkflowPhaseChangeHandler?
    var isRecording = false
    var audioLevel: Float = 0

    init(type: WorkflowType) {
        self.type = type
    }

    func start() {
        isRecording = true
        phase = .running("recording")
    }

    func stop() {
        isRecording = false
    }

    func reset() {
        phase = .idle
    }

    func emitOutput(_ text: String) {
        onOutput?(text)
    }
}

@MainActor
final class WorkflowLifecycleManagerTests: XCTestCase {

    @MainActor
    private final class WorkflowBox {
        var workflows: [FakeLifecycleWorkflow] = []
    }

    private func makeManager(
        available: Bool = true,
        isPopoverShown: @escaping () -> Bool = { false }
    ) -> (WorkflowLifecycleManager, workflows: WorkflowBox) {
        let box = WorkflowBox()
        let orchestrator = WorkflowOrchestrator(
            workflowFactory: { type, _ in
                guard available else { return nil }
                let workflow = FakeLifecycleWorkflow(type: type)
                box.workflows.append(workflow)
                return .workflow(workflow)
            },
            pasteAction: {},
            trustCheck: { _ in true },
            frontmostPidProvider: { nil },
            writeToPasteboard: { _ in }
        )
        let manager = WorkflowLifecycleManager(orchestrator: orchestrator, isPopoverShown: isPopoverShown)
        if !available {
            manager.startGate = { _ in
                WorkflowStartRejection(reason: "test", message: "nicht verfügbar", canRetryImmediately: false)
            }
        }
        return (manager, box)
    }

    func testStartRoutesToWorkflowPageWhenSourcePresentsWorkflowPage() {
        let (manager, _) = makeManager()
        var routedPage: PopoverPage?
        manager.onPageChangeNeeded = { page in routedPage = page }

        manager.start(.transcription, source: .manual, pasteTarget: nil)

        XCTAssertEqual(routedPage, .workflow)
    }

    func testStartRoutesToMainPageWhenSourceIsHotkeyBackground() {
        let (manager, _) = makeManager()
        var routedPage: PopoverPage?
        manager.onPageChangeNeeded = { page in routedPage = page }

        manager.start(.transcription, source: .hotkeyBackground, pasteTarget: nil)

        XCTAssertEqual(routedPage, .main)
    }

    func testStartReturnsStartedOutcomeWhenGateAllows() {
        let (manager, _) = makeManager()

        let outcome = manager.start(.transcription, source: .manual, pasteTarget: nil)

        XCTAssertEqual(outcome, .started)
    }

    func testStartRoutesToSettingsWhenRejectedAndSourceIsManual() {
        let (manager, _) = makeManager(available: false)
        var routedPage: PopoverPage?
        manager.onPageChangeNeeded = { page in routedPage = page }

        manager.start(.textImprover, source: .manual, pasteTarget: nil)

        XCTAssertEqual(routedPage, .settings)
    }

    /// Reverses the previous silent-veto expectation (#190, fixes F1 from #188): a
    /// rejected hotkey-triggered start must never create a workflow, but it must also
    /// never go unreported — the recording overlay's error state has to show it.
    func testStartReportsRejectionAndNeverCreatesWorkflowWhenSourceIsNotManual() {
        let (manager, workflows) = makeManager(available: false)
        var routedPage: PopoverPage?
        manager.onPageChangeNeeded = { page in routedPage = page }

        let outcome = manager.start(.textImprover, source: .hotkeyBackground, pasteTarget: nil)

        XCTAssertNil(routedPage)
        XCTAssertTrue(workflows.workflows.isEmpty)
        XCTAssertEqual(outcome, .rejected(
            WorkflowStartRejection(reason: "test", message: "nicht verfügbar", canRetryImmediately: false)
        ))
        XCTAssertEqual(manager.orchestrator.menuBarStatus, .error(.textImprover))
    }

    func testResetRoutesToMainPageAndClearsActiveWorkflow() {
        let (manager, _) = makeManager()
        manager.start(.transcription, source: .manual, pasteTarget: nil)
        var routedPage: PopoverPage?
        manager.onPageChangeNeeded = { page in routedPage = page }

        manager.reset()

        XCTAssertEqual(routedPage, .main)
        XCTAssertNil(manager.activeWorkflow)
    }

    // MARK: - Output-cleanup routing (popover-aware)

    func testOutputCleanupRoutesToMainPageWhenPopoverIsNotShown() {
        let (manager, workflows) = makeManager(isPopoverShown: { false })
        manager.start(.transcription, source: .manual, pasteTarget: nil)
        var routedPages: [PopoverPage] = []
        manager.onPageChangeNeeded = { page in routedPages.append(page) }

        workflows.workflows[0].phase = .done("output")
        workflows.workflows[0].emitOutput("hello")

        let expectation = expectation(description: "cleanup runs")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { expectation.fulfill() }
        wait(for: [expectation], timeout: 2)

        XCTAssertEqual(routedPages.last, .main)
    }

    func testOutputCleanupDoesNotRouteToMainPageWhenPopoverIsShown() {
        let (manager, workflows) = makeManager(isPopoverShown: { true })
        manager.start(.transcription, source: .manual, pasteTarget: nil)
        var routedPages: [PopoverPage] = []
        manager.onPageChangeNeeded = { page in routedPages.append(page) }

        workflows.workflows[0].phase = .done("output")
        workflows.workflows[0].emitOutput("hello")

        let expectation = expectation(description: "cleanup runs")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { expectation.fulfill() }
        wait(for: [expectation], timeout: 2)

        XCTAssertTrue(routedPages.isEmpty)
    }

    func testHotkeyBackgroundErrorRoutesToMainPageRegardlessOfPopover() {
        let (manager, workflows) = makeManager(isPopoverShown: { true })
        manager.start(.transcription, source: .hotkeyBackground, pasteTarget: nil)
        var routedPage: PopoverPage?
        manager.onPageChangeNeeded = { page in routedPage = page }

        workflows.workflows[0].phase = .error("boom")

        XCTAssertEqual(routedPage, .main)
    }
}
