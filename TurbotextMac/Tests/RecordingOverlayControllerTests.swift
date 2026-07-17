import XCTest
import AppKit
@testable import Turbotext

@MainActor
@Observable
private final class FakeOverlayWorkflow: Workflow {
    let type: WorkflowType
    var phase: WorkflowPhase = .idle { didSet { onPhaseChange?(phase) } }
    var onOutput: WorkflowOutputHandler?
    var onPhaseChange: WorkflowPhaseChangeHandler?
    var isRecording = false
    var audioLevel: Float = 0

    init(type: WorkflowType) { self.type = type }

    func start() {
        isRecording = true
        phase = .running("recording")
    }
    func stop() { isRecording = false }
    func reset() { phase = .idle }
}

@MainActor
private func makeOrchestratorWithWorkflow() -> (WorkflowOrchestrator, FakeOverlayWorkflow) {
    var createdWorkflow: FakeOverlayWorkflow!
    let orchestrator = WorkflowOrchestrator(
        workflowFactory: { type, _ in
            let workflow = FakeOverlayWorkflow(type: type)
            createdWorkflow = workflow
            return workflow
        },
        pasteAction: {},
        trustCheck: { _ in true },
        frontmostPidProvider: { nil },
        writeToPasteboard: { _ in }
    )
    orchestrator.start(.transcription, source: .manual, pasteTarget: nil)
    return (orchestrator, createdWorkflow)
}

@MainActor
final class RecordingOverlayControllerTests: XCTestCase {
    private let anchor = RecordingOverlayAnchor(point: CGPoint(x: 10, y: 20), source: .textCursor)

    func testOffModeNeverShowsOverlay() {
        let (orchestrator, _) = makeOrchestratorWithWorkflow()
        let controller = RecordingOverlayController(
            orchestrator: orchestrator,
            modeProvider: { .off },
            anchorResolver: { self.anchor }
        )

        controller.tick()

        XCTAssertEqual(controller.state, .hidden)
    }

    func testTextCursorModeShowsRecordingStateOnSuccessfulStart() {
        let (orchestrator, workflow) = makeOrchestratorWithWorkflow()
        let controller = RecordingOverlayController(
            orchestrator: orchestrator,
            modeProvider: { .textCursor },
            anchorResolver: { self.anchor },
            levelProvider: { workflow.audioLevel }
        )

        controller.tick()

        XCTAssertEqual(controller.state.phase, .recording)
        XCTAssertEqual(controller.state.anchor, anchor)
    }

    func testAnchorIsResolvedOnceForTheRecordingLifetime() {
        let (orchestrator, workflow) = makeOrchestratorWithWorkflow()
        var resolveCount = 0
        let controller = RecordingOverlayController(
            orchestrator: orchestrator,
            modeProvider: { .textCursor },
            anchorResolver: {
                resolveCount += 1
                return self.anchor
            },
            levelProvider: { workflow.audioLevel }
        )

        controller.tick()
        controller.tick()
        controller.tick()

        XCTAssertEqual(resolveCount, 1)
    }

    func testLevelsAreSampledIntoHistoryWhileRecording() {
        let (orchestrator, workflow) = makeOrchestratorWithWorkflow()
        var level: Float = 0.2
        let controller = RecordingOverlayController(
            orchestrator: orchestrator,
            modeProvider: { .textCursor },
            anchorResolver: { self.anchor },
            levelProvider: { level }
        )

        controller.tick()
        level = 0.8
        controller.tick()

        XCTAssertEqual(controller.state.levelHistory, [0.2, 0.8])
    }

    func testOverlayHidesAfterWorkflowReturnsToIdle() {
        let (orchestrator, workflow) = makeOrchestratorWithWorkflow()
        let controller = RecordingOverlayController(
            orchestrator: orchestrator,
            modeProvider: { .textCursor },
            anchorResolver: { self.anchor },
            levelProvider: { workflow.audioLevel }
        )
        controller.tick()
        XCTAssertEqual(controller.state.phase, .recording)

        orchestrator.reset()
        controller.tick()

        XCTAssertEqual(controller.state, .hidden)
    }

    func testPanelNeverBecomesKeyOrMainAndIgnoresMouse() throws {
        let (orchestrator, workflow) = makeOrchestratorWithWorkflow()
        let controller = RecordingOverlayController(
            orchestrator: orchestrator,
            modeProvider: { .textCursor },
            anchorResolver: { self.anchor },
            levelProvider: { workflow.audioLevel }
        )

        controller.tick()

        let panel = try XCTUnwrap(controller.debugPanel)
        XCTAssertFalse(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
        XCTAssertTrue(panel.ignoresMouseEvents)
        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertEqual(panel.level, .floating)
        XCTAssertEqual(
            panel.collectionBehavior,
            [.auxiliary, .fullScreenAuxiliary, .canJoinAllSpaces, .ignoresCycle]
        )
    }
}
