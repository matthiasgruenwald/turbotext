import XCTest
import AppKit
@testable import Turbotext

@MainActor
@Observable
private final class FakeWorkflow: Workflow {
    let type: WorkflowType
    var phase: WorkflowPhase = .idle {
        didSet { onPhaseChange?(phase) }
    }
    var onOutput: WorkflowOutputHandler?
    var onPhaseChange: WorkflowPhaseChangeHandler?
    var isRecording = false
    var audioLevel: Float = 0

    var startCallCount = 0
    var stopCallCount = 0
    var resetCallCount = 0

    init(type: WorkflowType) {
        self.type = type
    }

    func start() {
        startCallCount += 1
        isRecording = true
        phase = .running("recording")
    }

    func stop() {
        stopCallCount += 1
        isRecording = false
    }

    func reset() {
        resetCallCount += 1
        phase = .idle
    }

    func emitOutput(_ text: String) {
        onOutput?(text)
    }
}

@MainActor
private func makeFakePasteTarget(pid: pid_t = 4242) -> PasteTarget {
    PasteTarget(
        bundleIdentifier: "com.example.target",
        processIdentifier: pid,
        application: NSRunningApplication.current
    )
}

/// Collects the `FakeWorkflow` instances a test's injected factory creates,
/// so assertions can inspect them after `start()` returns.
@MainActor
private final class WorkflowBox {
    var workflows: [FakeWorkflow] = []
}

@MainActor
private func makeOrchestrator(
    createdWorkflows box: WorkflowBox,
    frontmostPid: pid_t? = nil,
    trusted: Bool = true
) -> WorkflowOrchestrator {
    WorkflowOrchestrator(
        workflowFactory: { type, _ in
            let workflow = FakeWorkflow(type: type)
            box.workflows.append(workflow)
            return workflow
        },
        pasteAction: {},
        trustCheck: { _ in trusted },
        frontmostPidProvider: { frontmostPid },
        writeToPasteboard: { _ in }
    )
}

@MainActor
final class WorkflowOrchestratorTests: XCTestCase {

    // MARK: - Starting each of the 5 workflow types

    func testStartingEachWorkflowTypeInvokesFactoryAndCallsStart() {
        for type in WorkflowType.allCases {
            let box = WorkflowBox()
            let orchestrator = makeOrchestrator(createdWorkflows: box)

            orchestrator.start(type, source: .manual, pasteTarget: nil)

            XCTAssertEqual(box.workflows.count, 1, "expected exactly one workflow created for \(type)")
            XCTAssertEqual(box.workflows.first?.type, type)
            XCTAssertEqual(box.workflows.first?.startCallCount, 1)
            XCTAssertTrue(orchestrator.activeWorkflow is FakeWorkflow)
        }
    }

    func testStartingNewWorkflowStopsPreviouslyActiveOne() {
        let box = WorkflowBox()
        let orchestrator = makeOrchestrator(createdWorkflows: box)

        orchestrator.start(.transcription, source: .manual, pasteTarget: nil)
        let first = box.workflows[0]
        orchestrator.start(.emojiText, source: .manual, pasteTarget: nil)

        XCTAssertEqual(first.stopCallCount, 1)
        XCTAssertEqual(box.workflows.count, 2)
        XCTAssertEqual((orchestrator.activeWorkflow as? FakeWorkflow)?.type, .emojiText)
    }

    func testFactoryReturningNilLeavesNoActiveWorkflow() {
        let orchestrator = WorkflowOrchestrator(workflowFactory: { _, _ in nil })

        orchestrator.start(.transcription, source: .manual, pasteTarget: nil)

        XCTAssertNil(orchestrator.activeWorkflow)
    }

    // MARK: - Phase transitions

    func testRunningPhaseSetsRecordingMenuBarStatusWhenRecording() {
        let box = WorkflowBox()
        let orchestrator = makeOrchestrator(createdWorkflows: box)

        orchestrator.start(.transcription, source: .manual, pasteTarget: nil)

        XCTAssertEqual(orchestrator.menuBarStatus, .recording(.transcription))
    }

    func testProcessingPhaseSetsProcessingMenuBarStatusWhenNotRecording() {
        let box = WorkflowBox()
        let orchestrator = makeOrchestrator(createdWorkflows: box)

        orchestrator.start(.transcription, source: .manual, pasteTarget: nil)
        box.workflows[0].isRecording = false
        box.workflows[0].phase = .running("processing")

        XCTAssertEqual(orchestrator.menuBarStatus, .processing(.transcription))
    }

    func testDonePhaseSetsSuccessMenuBarStatus() {
        let box = WorkflowBox()
        let orchestrator = makeOrchestrator(createdWorkflows: box)

        orchestrator.start(.transcription, source: .manual, pasteTarget: nil)
        box.workflows[0].phase = .done("output")

        XCTAssertEqual(orchestrator.menuBarStatus, .success(.transcription))
    }

    func testErrorPhaseSetsErrorMenuBarStatus() {
        let box = WorkflowBox()
        let orchestrator = makeOrchestrator(createdWorkflows: box)

        orchestrator.start(.transcription, source: .manual, pasteTarget: nil)
        box.workflows[0].phase = .error("boom")

        XCTAssertEqual(orchestrator.menuBarStatus, .error(.transcription))
    }

    func testErrorPhaseCapturesLastErrorMessage() {
        let box = WorkflowBox()
        let orchestrator = makeOrchestrator(createdWorkflows: box)

        orchestrator.start(.transcription, source: .manual, pasteTarget: nil)
        box.workflows[0].phase = .error("Kein Mikrofon verfügbar.")

        XCTAssertEqual(orchestrator.lastErrorMessage, "Kein Mikrofon verfügbar.")
    }

    func testErrorPhaseDuringHotkeyBackgroundClearsActiveWorkflowAndNotifiesFinished() {
        let box = WorkflowBox()
        let orchestrator = makeOrchestrator(createdWorkflows: box)
        var finishedReasons: [WorkflowOrchestrator.FinishReason] = []
        orchestrator.onWorkflowFinished = { finishedReasons.append($0) }

        orchestrator.start(.transcription, source: .hotkeyBackground, pasteTarget: nil)
        box.workflows[0].phase = .error("boom")

        XCTAssertNil(orchestrator.activeWorkflow)
        XCTAssertEqual(finishedReasons, [.errorDuringBackgroundLaunch])
    }

    func testErrorPhaseDuringManualLaunchKeepsActiveWorkflow() {
        let box = WorkflowBox()
        let orchestrator = makeOrchestrator(createdWorkflows: box)

        orchestrator.start(.transcription, source: .manual, pasteTarget: nil)
        box.workflows[0].phase = .error("boom")

        XCTAssertNotNil(orchestrator.activeWorkflow)
    }

    // MARK: - Stop / Reset

    func testStopDelegatesToActiveWorkflow() {
        let box = WorkflowBox()
        let orchestrator = makeOrchestrator(createdWorkflows: box)

        orchestrator.start(.transcription, source: .manual, pasteTarget: nil)
        orchestrator.stop()

        XCTAssertEqual(box.workflows[0].stopCallCount, 1)
    }

    func testResetClearsActiveWorkflowAndMenuBarStatus() {
        let box = WorkflowBox()
        let orchestrator = makeOrchestrator(createdWorkflows: box)

        orchestrator.start(.transcription, source: .manual, pasteTarget: nil)
        orchestrator.reset()

        XCTAssertEqual(box.workflows[0].resetCallCount, 1)
        XCTAssertNil(orchestrator.activeWorkflow)
        XCTAssertEqual(orchestrator.menuBarStatus, .idle)
    }

    // MARK: - Target app binding (activePasteTargetProcessIdentifier)

    /// `RecordingOverlayController` reads this to bind the text-cursor overlay to the
    /// specific app captured at start, independent of whichever app the user later focuses.
    func testActivePasteTargetProcessIdentifierReflectsTheCapturedTarget() {
        let box = WorkflowBox()
        let orchestrator = makeOrchestrator(createdWorkflows: box)
        let target = makeFakePasteTarget(pid: 777)

        orchestrator.start(.transcription, source: .manual, pasteTarget: target)

        XCTAssertEqual(orchestrator.activePasteTargetProcessIdentifier, 777)
    }

    func testActivePasteTargetProcessIdentifierIsNilWithoutACapturedTarget() {
        let box = WorkflowBox()
        let orchestrator = makeOrchestrator(createdWorkflows: box)

        orchestrator.start(.transcription, source: .manual, pasteTarget: nil)

        XCTAssertNil(orchestrator.activePasteTargetProcessIdentifier)
    }

    func testActivePasteTargetProcessIdentifierClearsOnReset() {
        let box = WorkflowBox()
        let orchestrator = makeOrchestrator(createdWorkflows: box)
        let target = makeFakePasteTarget(pid: 777)

        orchestrator.start(.transcription, source: .manual, pasteTarget: target)
        orchestrator.reset()

        XCTAssertNil(orchestrator.activePasteTargetProcessIdentifier)
    }

    // MARK: - Paste retry-on-failure path

    func testPasteSucceedsImmediatelyWhenTargetAlreadyFrontmost() {
        let target = makeFakePasteTarget(pid: 99)
        var pasteCount = 0
        var activationCount = 0
        let orchestrator = WorkflowOrchestrator(
            workflowFactory: { type, _ in FakeWorkflow(type: type) },
            pasteAction: { pasteCount += 1 },
            trustCheck: { _ in true },
            frontmostPidProvider: { 99 },
            writeToPasteboard: { _ in }
        )
        orchestrator.onPasteTargetActivationNeeded = { _ in activationCount += 1 }

        orchestrator.pasteAtCursor("hello", target: target)

        XCTAssertEqual(pasteCount, 1)
        XCTAssertEqual(activationCount, 0)
    }

    func testPasteRetriesActivationUntilTargetBecomesFrontmost() {
        let target = makeFakePasteTarget(pid: 99)
        var currentFrontmostPid: pid_t? = 1
        var pasteCount = 0
        var activationCount = 0

        let orchestrator = WorkflowOrchestrator(
            workflowFactory: { type, _ in FakeWorkflow(type: type) },
            pasteAction: { pasteCount += 1 },
            trustCheck: { _ in true },
            frontmostPidProvider: { currentFrontmostPid },
            writeToPasteboard: { _ in }
        )
        orchestrator.onPasteTargetActivationNeeded = { _ in
            activationCount += 1
            // Simulate the OS activating the target app after the first nudge.
            currentFrontmostPid = 99
        }

        let expectation = expectation(description: "paste eventually succeeds")
        orchestrator.pasteAtCursor("hello", target: target)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2)

        XCTAssertGreaterThanOrEqual(activationCount, 1)
        XCTAssertEqual(pasteCount, 1)
    }

    func testPasteDoesNothingWhenNoTargetProvided() {
        var pasteCount = 0
        let orchestrator = WorkflowOrchestrator(
            workflowFactory: { type, _ in FakeWorkflow(type: type) },
            pasteAction: { pasteCount += 1 },
            trustCheck: { _ in true },
            frontmostPidProvider: { nil },
            writeToPasteboard: { _ in }
        )

        orchestrator.pasteAtCursor("hello", target: nil)

        XCTAssertEqual(pasteCount, 0)
    }

    func testPasteSetsErrorMenuBarStatusWhenNotTrusted() {
        let box = WorkflowBox()
        let orchestrator = makeOrchestrator(createdWorkflows: box, trusted: false)

        orchestrator.start(.transcription, source: .manual, pasteTarget: nil)
        box.workflows[0].emitOutput("hello")

        XCTAssertEqual(orchestrator.menuBarStatus, .error(.transcription))
        XCTAssertFalse(orchestrator.accessibilityPermissionGranted)
    }

    // MARK: - Extended retry window and failure signal (#176)

    /// Polls on the main run loop until `condition` holds; robust against retry-chain
    /// scheduling jitter, which fixed `asyncAfter` waits are not.
    private func waitUntil(timeout: TimeInterval = 5, _ condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else {
                XCTFail("condition not met within \(timeout)s")
                return
            }
            let tick = expectation(description: "poll tick")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { tick.fulfill() }
            wait(for: [tick], timeout: 1)
        }
    }

    func testPasteSucceedsWhenTargetActivationTakesAboutOneSecond() {
        let target = makeFakePasteTarget(pid: 99)
        var currentFrontmostPid: pid_t? = 1
        var pasteCount = 0
        let orchestrator = WorkflowOrchestrator(
            workflowFactory: { type, _ in FakeWorkflow(type: type) },
            pasteAction: { pasteCount += 1 },
            trustCheck: { _ in true },
            frontmostPidProvider: { currentFrontmostPid },
            writeToPasteboard: { _ in }
        )

        orchestrator.pasteAtCursor("hello", target: target)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            currentFrontmostPid = 99
        }

        waitUntil { pasteCount == 1 }

        XCTAssertEqual(pasteCount, 1, "the ~1.5s retry window must cover target activations that take ~1s")
        XCTAssertNil(orchestrator.pasteFailureMessage)
    }

    func testPasteExhaustionSignalsFailureWithoutPasting() {
        let target = makeFakePasteTarget(pid: 99)
        var pasteCount = 0
        var pasteboardWrites: [String] = []
        let orchestrator = WorkflowOrchestrator(
            workflowFactory: { type, _ in FakeWorkflow(type: type) },
            pasteAction: { pasteCount += 1 },
            trustCheck: { _ in true },
            frontmostPidProvider: { 1 },
            writeToPasteboard: { pasteboardWrites.append($0) }
        )

        orchestrator.pasteAtCursor("hello", target: target)
        waitUntil { orchestrator.pasteFailureMessage != nil }

        XCTAssertEqual(pasteCount, 0)
        XCTAssertEqual(orchestrator.takePasteFailureMessage(), WorkflowOrchestrator.pasteRetryExhaustedMessage)
        XCTAssertEqual(orchestrator.menuBarStatus, .error(nil))
        XCTAssertEqual(pasteboardWrites, ["hello"], "the clipboard fallback must stay filled")
        XCTAssertNil(orchestrator.takePasteFailureMessage(), "the failure message must be consumed exactly once")
    }

    func testPasteExhaustionFailureArrivesAfterWorkflowCleanup() {
        let target = makeFakePasteTarget(pid: 99)
        let box = WorkflowBox()
        var pasteCount = 0
        let orchestrator = WorkflowOrchestrator(
            workflowFactory: { type, _ in
                let workflow = FakeWorkflow(type: type)
                box.workflows.append(workflow)
                return workflow
            },
            pasteAction: { pasteCount += 1 },
            trustCheck: { _ in true },
            frontmostPidProvider: { 1 },
            writeToPasteboard: { _ in }
        )

        orchestrator.start(.transcription, source: .manual, pasteTarget: target)
        box.workflows[0].emitOutput("hello")

        let cleanupElapsed = expectation(description: "workflow cleanup ran before retry exhaustion")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            XCTAssertNil(orchestrator.activeWorkflow, "sanity: the 1.05s cleanup already reset the workflow")
            XCTAssertNil(orchestrator.pasteFailureMessage, "sanity: retries are still running at 1.2s")
            cleanupElapsed.fulfill()
        }
        wait(for: [cleanupElapsed], timeout: 3)

        waitUntil { orchestrator.pasteFailureMessage != nil }

        XCTAssertEqual(pasteCount, 0)
        XCTAssertEqual(orchestrator.takePasteFailureMessage(), WorkflowOrchestrator.pasteRetryExhaustedMessage)
        XCTAssertEqual(orchestrator.menuBarStatus, .error(.transcription))
    }

    func testStartClearsPendingPasteFailureMessage() {
        let target = makeFakePasteTarget(pid: 99)
        let orchestrator = WorkflowOrchestrator(
            workflowFactory: { type, _ in FakeWorkflow(type: type) },
            pasteAction: {},
            trustCheck: { _ in true },
            frontmostPidProvider: { 1 },
            writeToPasteboard: { _ in }
        )

        orchestrator.pasteAtCursor("hello", target: target)
        waitUntil { orchestrator.pasteFailureMessage != nil }

        orchestrator.start(.transcription, source: .manual, pasteTarget: target)

        XCTAssertNil(orchestrator.pasteFailureMessage)
        XCTAssertNil(orchestrator.takePasteFailureMessage())
    }

    func testOutputDeliveryWritesToPasteboardAndAttemptsPaste() {
        var pasteCount = 0
        var pasteboardWrites: [String] = []
        let target = makeFakePasteTarget(pid: 99)
        let box = WorkflowBox()

        let orchestrator = WorkflowOrchestrator(
            workflowFactory: { type, _ in
                let workflow = FakeWorkflow(type: type)
                box.workflows.append(workflow)
                return workflow
            },
            pasteAction: { pasteCount += 1 },
            trustCheck: { _ in true },
            frontmostPidProvider: { 99 },
            writeToPasteboard: { pasteboardWrites.append($0) }
        )

        orchestrator.start(.transcription, source: .manual, pasteTarget: target)
        box.workflows[0].emitOutput("transcribed text")

        XCTAssertEqual(pasteboardWrites, ["transcribed text"])
        XCTAssertEqual(pasteCount, 1)
    }

    // MARK: - Live transcript display (#151)

    func testUpdateLiveTranscriptDisplayStoresTheDisplay() {
        let box = WorkflowBox()
        let orchestrator = makeOrchestrator(createdWorkflows: box)
        let display = LiveTranscriptDisplay(finalText: "Fest.", volatileText: "flüchtig", maxLines: 3)

        orchestrator.updateLiveTranscriptDisplay(display)

        XCTAssertEqual(orchestrator.lastLiveTranscriptDisplay, display)
    }

    func testUpdatePartialTranscriptWrapsAsVolatileDisplay() {
        let box = WorkflowBox()
        let orchestrator = makeOrchestrator(createdWorkflows: box)

        orchestrator.updatePartialTranscript("Hallo")

        XCTAssertEqual(orchestrator.lastLiveTranscriptDisplay?.volatileText, "Hallo")
        XCTAssertEqual(orchestrator.lastLiveTranscriptDisplay?.finalText, "")
    }

    func testStartResetsLiveTranscriptDisplayAndBergungMessage() {
        let box = WorkflowBox()
        let orchestrator = makeOrchestrator(createdWorkflows: box)
        orchestrator.updateLiveTranscriptDisplay(LiveTranscriptDisplay(volatileText: "alt"))
        orchestrator.reportBergung(message: "boom")

        orchestrator.start(.transcription, source: .manual, pasteTarget: nil)

        XCTAssertNil(orchestrator.lastLiveTranscriptDisplay)
        XCTAssertNil(orchestrator.bergungMessage)
    }

    func testReportBergungStoresMessage() {
        let box = WorkflowBox()
        let orchestrator = makeOrchestrator(createdWorkflows: box)

        orchestrator.reportBergung(message: "Engine-Fehler")

        XCTAssertEqual(orchestrator.bergungMessage, "Engine-Fehler")
    }
}
