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
                return workflow
            },
            pasteAction: {},
            trustCheck: { _ in true },
            frontmostPidProvider: { nil },
            writeToPasteboard: { _ in }
        )
        let manager = WorkflowLifecycleManager(orchestrator: orchestrator, isPopoverShown: isPopoverShown)
        return (manager, box)
    }

    func testStartRoutesToWorkflowPageWhenSourcePresentsWorkflowPage() {
        let (manager, _) = makeManager()
        var routedPage: PopoverPage?
        manager.onPageChangeNeeded = { page in routedPage = page }

        manager.start(.transcription, source: .manual, isAvailable: true, pasteTarget: nil)

        XCTAssertEqual(routedPage, .workflow)
    }

    func testStartRoutesToMainPageWhenSourceIsHotkeyBackground() {
        let (manager, _) = makeManager()
        var routedPage: PopoverPage?
        manager.onPageChangeNeeded = { page in routedPage = page }

        manager.start(.transcription, source: .hotkeyBackground, isAvailable: true, pasteTarget: nil)

        XCTAssertEqual(routedPage, .main)
    }

    func testStartRoutesToSettingsWhenUnavailableAndSourceIsManual() {
        let (manager, _) = makeManager(available: false)
        var routedPage: PopoverPage?
        manager.onPageChangeNeeded = { page in routedPage = page }

        manager.start(.textImprover, source: .manual, isAvailable: false, pasteTarget: nil)

        XCTAssertEqual(routedPage, .settings)
    }

    func testStartDoesNothingWhenUnavailableAndSourceIsNotManual() {
        let (manager, workflows) = makeManager(available: false)
        var routedPage: PopoverPage?
        manager.onPageChangeNeeded = { page in routedPage = page }

        manager.start(.textImprover, source: .hotkeyBackground, isAvailable: false, pasteTarget: nil)

        XCTAssertNil(routedPage)
        XCTAssertTrue(workflows.workflows.isEmpty)
    }

    func testResetRoutesToMainPageAndClearsActiveWorkflow() {
        let (manager, _) = makeManager()
        manager.start(.transcription, source: .manual, isAvailable: true, pasteTarget: nil)
        var routedPage: PopoverPage?
        manager.onPageChangeNeeded = { page in routedPage = page }

        manager.reset()

        XCTAssertEqual(routedPage, .main)
        XCTAssertNil(manager.activeWorkflow)
    }

    // MARK: - Output-cleanup routing (popover-aware)

    func testOutputCleanupRoutesToMainPageWhenPopoverIsNotShown() {
        let (manager, workflows) = makeManager(isPopoverShown: { false })
        manager.start(.transcription, source: .manual, isAvailable: true, pasteTarget: nil)
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
        manager.start(.transcription, source: .manual, isAvailable: true, pasteTarget: nil)
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
        manager.start(.transcription, source: .hotkeyBackground, isAvailable: true, pasteTarget: nil)
        var routedPage: PopoverPage?
        manager.onPageChangeNeeded = { page in routedPage = page }

        workflows.workflows[0].phase = .error("boom")

        XCTAssertEqual(routedPage, .main)
    }
}
