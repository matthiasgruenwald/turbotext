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

    private func makeManager(
        available: Bool = true
    ) -> (WorkflowLifecycleManager, workflows: [FakeLifecycleWorkflow]) {
        var created: [FakeLifecycleWorkflow] = []
        let orchestrator = WorkflowOrchestrator(
            workflowFactory: { type, _ in
                guard available else { return nil }
                let workflow = FakeLifecycleWorkflow(type: type)
                created.append(workflow)
                return workflow
            },
            pasteAction: {},
            trustCheck: { _ in true },
            frontmostPidProvider: { nil },
            writeToPasteboard: { _ in }
        )
        let manager = WorkflowLifecycleManager(orchestrator: orchestrator)
        return (manager, created)
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
        XCTAssertTrue(workflows.isEmpty)
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
}
