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
    /// When set, `start()` fails immediately with this message instead of recording —
    /// simulates a known recording-start error (e.g. no microphone) deterministically.
    var startErrorMessage: String?

    init(type: WorkflowType) { self.type = type }

    func start() {
        if let startErrorMessage {
            phase = .error(startErrorMessage)
            return
        }
        isRecording = true
        phase = .running("recording")
    }
    func stop() { isRecording = false }
    func reset() { phase = .idle }
}

@MainActor
private func makeOrchestratorWithWorkflow(pasteTarget: PasteTarget? = nil) -> (WorkflowOrchestrator, FakeOverlayWorkflow) {
    var createdWorkflow: FakeOverlayWorkflow!
    let orchestrator = WorkflowOrchestrator(
        workflowFactory: { type in
            let workflow = FakeOverlayWorkflow(type: type)
            createdWorkflow = workflow
            return .workflow(workflow)
        },
        pasteAction: {},
        trustCheck: { _ in true },
        frontmostPidProvider: { nil },
        writeToPasteboard: { _ in }
    )
    orchestrator.start(.transcription, source: .manual, pasteTarget: pasteTarget)
    return (orchestrator, createdWorkflow)
}

private func makeFakePasteTarget(pid: pid_t) -> PasteTarget {
    PasteTarget(bundleIdentifier: "com.example.target", processIdentifier: pid, application: NSRunningApplication.current)
}

@MainActor
private func makeOrchestratorWithFailingStart(message: String) -> WorkflowOrchestrator {
    WorkflowOrchestrator(
        workflowFactory: { type in
            let workflow = FakeOverlayWorkflow(type: type)
            workflow.startErrorMessage = message
            return .workflow(workflow)
        },
        pasteAction: {},
        trustCheck: { _ in true },
        frontmostPidProvider: { nil },
        writeToPasteboard: { _ in }
    )
}

@MainActor
final class RecordingOverlayControllerTests: XCTestCase {
    private let anchor = RecordingOverlayAnchor(point: CGPoint(x: 10, y: 20), source: .screenBottomCenter)

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

    func testScreenBottomCenterModeShowsRecordingStateOnSuccessfulStart() {
        let (orchestrator, workflow) = makeOrchestratorWithWorkflow()
        let controller = RecordingOverlayController(
            orchestrator: orchestrator,
            modeProvider: { .screenBottomCenter },
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
            modeProvider: { .screenBottomCenter },
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
        let (orchestrator, _) = makeOrchestratorWithWorkflow()
        var level: Float = 0.2
        let controller = RecordingOverlayController(
            orchestrator: orchestrator,
            modeProvider: { .screenBottomCenter },
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
            modeProvider: { .screenBottomCenter },
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
            modeProvider: { .screenBottomCenter },
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

    // MARK: - Known start errors

    func testKnownStartErrorShowsErrorPhaseWithMessage() {
        let orchestrator = makeOrchestratorWithFailingStart(message: "Kein Mikrofon verfügbar.")
        orchestrator.start(.transcription, source: .manual, pasteTarget: nil)
        let controller = RecordingOverlayController(
            orchestrator: orchestrator,
            modeProvider: { .screenBottomCenter },
            anchorResolver: { self.anchor }
        )

        controller.tick()

        XCTAssertEqual(controller.state.phase, .error)
        XCTAssertEqual(controller.state.errorMessage, "Kein Mikrofon verfügbar.")
    }

    func testErrorPanelAcceptsMouseEventsSoItCanBeClosedManually() throws {
        let orchestrator = makeOrchestratorWithFailingStart(message: "boom")
        orchestrator.start(.transcription, source: .manual, pasteTarget: nil)
        let controller = RecordingOverlayController(
            orchestrator: orchestrator,
            modeProvider: { .screenBottomCenter },
            anchorResolver: { self.anchor }
        )

        controller.tick()

        let panel = try XCTUnwrap(controller.debugPanel)
        XCTAssertFalse(panel.ignoresMouseEvents, "the error pill must be clickable so it can be dismissed manually")
    }

    func testDismissErrorHidesTheOverlayImmediately() {
        let orchestrator = makeOrchestratorWithFailingStart(message: "boom")
        orchestrator.start(.transcription, source: .manual, pasteTarget: nil)
        let controller = RecordingOverlayController(
            orchestrator: orchestrator,
            modeProvider: { .screenBottomCenter },
            anchorResolver: { self.anchor }
        )
        controller.tick()
        XCTAssertEqual(controller.state.phase, .error)

        controller.dismissError()

        XCTAssertEqual(controller.state, .hidden)
    }

    func testErrorAutoDismissesAfterFiveSecondsOfPolling() {
        let orchestrator = makeOrchestratorWithFailingStart(message: "boom")
        orchestrator.start(.transcription, source: .manual, pasteTarget: nil)
        let controller = RecordingOverlayController(
            orchestrator: orchestrator,
            modeProvider: { .screenBottomCenter },
            anchorResolver: { self.anchor }
        )

        for _ in 0..<25 {
            controller.tick()
        }
        XCTAssertEqual(
            controller.state.phase, .error,
            "must still be visible halfway through the 5s window, not hidden by the orchestrator repeating the same status"
        )

        for _ in 0..<25 {
            controller.tick()
        }
        XCTAssertEqual(controller.state, .hidden)
    }

    /// Regression: `WorkflowOrchestrator` resets `menuBarStatus` to `.idle` on its own
    /// ~1.6s after a hotkey-background start error — well before the pill's 5s window.
    /// The overlay must keep showing the error through that reset.
    func testErrorSurvivesTheOrchestratorsOwnMenuBarStatusResetForHotkeyBackgroundSource() {
        let orchestrator = makeOrchestratorWithFailingStart(message: "boom")
        orchestrator.start(.transcription, source: .hotkeyBackground, pasteTarget: nil)
        let controller = RecordingOverlayController(
            orchestrator: orchestrator,
            modeProvider: { .screenBottomCenter },
            anchorResolver: { self.anchor }
        )

        controller.tick()
        XCTAssertEqual(controller.state.phase, .error)

        let resetExpectation = expectation(description: "orchestrator resets menuBarStatus to idle")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            XCTAssertEqual(orchestrator.menuBarStatus, .idle, "sanity check: the orchestrator really did reset on its own")
            resetExpectation.fulfill()
        }
        wait(for: [resetExpectation], timeout: 3)

        controller.tick()
        XCTAssertEqual(controller.state.phase, .error, "the pill must still be showing despite the orchestrator's own reset")
    }

    // MARK: - Silence hint

    func testSilenceHintAppearsAfterFiveSecondsOfPollingWithoutSignal() {
        let (orchestrator, _) = makeOrchestratorWithWorkflow()
        let controller = RecordingOverlayController(
            orchestrator: orchestrator,
            modeProvider: { .screenBottomCenter },
            anchorResolver: { self.anchor },
            levelProvider: { 0 }
        )

        for _ in 0..<50 {
            controller.tick()
        }

        XCTAssertEqual(controller.state.phase, .recording, "recording keeps running while the hint is shown")
        XCTAssertTrue(controller.state.showsSilenceHint)
    }

    // MARK: - Live transcript display (#150)

    func testLiveTranscriptAppearsWhileRecording() {
        let (orchestrator, _) = makeOrchestratorWithWorkflow()
        var partial = "Hallo"
        let controller = RecordingOverlayController(
            orchestrator: orchestrator,
            modeProvider: { .screenBottomCenter },
            anchorResolver: { self.anchor },
            levelProvider: { 0 },
            liveTranscriptDisplayProvider: { LiveTranscriptDisplay(volatileText: partial) }
        )

        controller.tick()
        XCTAssertEqual(controller.state.liveTranscriptDisplay?.volatileText, "Hallo")

        partial = "Hallo Welt"
        controller.tick()
        XCTAssertEqual(controller.state.liveTranscriptDisplay?.volatileText, "Hallo Welt")
    }

    func testLiveTranscriptStaysNilWithoutAppleSpeech() {
        let (orchestrator, _) = makeOrchestratorWithWorkflow()
        let controller = RecordingOverlayController(
            orchestrator: orchestrator,
            modeProvider: { .screenBottomCenter },
            anchorResolver: { self.anchor },
            levelProvider: { 0 },
            liveTranscriptDisplayProvider: { nil }
        )

        controller.tick()

        XCTAssertNil(controller.state.liveTranscriptDisplay)
    }

    // MARK: - Processing / completion labels (#128)

    func testProcessingLabelIsShownWhileProcessing() {
        let (orchestrator, workflow) = makeOrchestratorWithWorkflow()
        let controller = RecordingOverlayController(
            orchestrator: orchestrator,
            modeProvider: { .screenBottomCenter },
            anchorResolver: { self.anchor },
            levelProvider: { workflow.audioLevel },
            processingLabelProvider: { "Nachbearbeitung läuft – lokal auf diesem Mac" }
        )
        controller.tick()

        workflow.isRecording = false
        workflow.phase = .running("Wird verarbeitet ...")
        controller.tick()

        XCTAssertEqual(controller.state.phase, .processing)
        XCTAssertEqual(controller.state.processingLabel, "Nachbearbeitung läuft – lokal auf diesem Mac")
    }

    func testCompletionLabelAppearsAfterProcessingAndAutoDismissesAfterThreeSeconds() {
        let (orchestrator, workflow) = makeOrchestratorWithWorkflow()
        let controller = RecordingOverlayController(
            orchestrator: orchestrator,
            modeProvider: { .screenBottomCenter },
            anchorResolver: { self.anchor },
            levelProvider: { workflow.audioLevel },
            completionLabelProvider: { "Text lokal verbessert · Apple Foundation Models" }
        )
        controller.tick()
        workflow.isRecording = false
        workflow.phase = .running("Wird verarbeitet ...")
        controller.tick()

        orchestrator.reset()
        controller.tick()

        XCTAssertEqual(controller.state.phase, .completion)
        XCTAssertEqual(controller.state.completionLabel, "Text lokal verbessert · Apple Foundation Models")

        for _ in 0..<30 {
            controller.tick()
        }
        XCTAssertEqual(controller.state, .hidden)
    }

    func testDismissCompletionLabelHidesOverlayAndFiresCallback() {
        let (orchestrator, workflow) = makeOrchestratorWithWorkflow()
        let controller = RecordingOverlayController(
            orchestrator: orchestrator,
            modeProvider: { .screenBottomCenter },
            anchorResolver: { self.anchor },
            levelProvider: { workflow.audioLevel },
            completionLabelProvider: { "Text lokal verbessert · Apple Foundation Models" }
        )
        var dismissed = false
        controller.onCompletionLabelDismissed = { dismissed = true }

        controller.tick()
        workflow.isRecording = false
        workflow.phase = .running("Wird verarbeitet ...")
        controller.tick()
        orchestrator.reset()
        controller.tick()
        XCTAssertEqual(controller.state.phase, .completion)

        controller.dismissCompletionLabel()

        XCTAssertEqual(controller.state, .hidden)
        XCTAssertTrue(dismissed)
    }

    // MARK: - Target-screen positioning

    func testScreenBottomCenterModeFallsBackToThePrimaryScreenWithoutACapturedTarget() {
        let (orchestrator, workflow) = makeOrchestratorWithWorkflow()
        let bottomCenter = CGPoint(x: 640, y: 40)
        let controller = RecordingOverlayController(
            orchestrator: orchestrator,
            modeProvider: { .screenBottomCenter },
            targetScreenBottomCenterProvider: { _ in
                XCTFail("must not resolve a target screen without a captured target app")
                return nil
            },
            screenBottomCenterProvider: { bottomCenter },
            levelProvider: { workflow.audioLevel }
        )

        controller.tick()

        XCTAssertEqual(controller.state.anchor?.point, bottomCenter)
        XCTAssertEqual(controller.state.anchor?.source, .screenBottomCenter)
    }

    func testScreenBottomCenterModeUsesTheCapturedTargetAppsScreen() {
        let target = makeFakePasteTarget(pid: 4242)
        let (orchestrator, workflow) = makeOrchestratorWithWorkflow(pasteTarget: target)
        let controller = RecordingOverlayController(
            orchestrator: orchestrator,
            modeProvider: { .screenBottomCenter },
            targetScreenBottomCenterProvider: { pid in
                XCTAssertEqual(pid, 4242)
                return CGPoint(x: 1_920, y: 40)
            },
            screenBottomCenterProvider: { CGPoint(x: 640, y: 40) },
            levelProvider: { workflow.audioLevel }
        )

        controller.tick()

        XCTAssertEqual(controller.state.anchor?.point, CGPoint(x: 1_920, y: 40))
    }

    func testScreenBottomCenterModeFallsBackToThePrimaryScreenWhenTargetScreenIsUnavailable() {
        let target = makeFakePasteTarget(pid: 4242)
        let (orchestrator, workflow) = makeOrchestratorWithWorkflow(pasteTarget: target)
        let controller = RecordingOverlayController(
            orchestrator: orchestrator,
            modeProvider: { .screenBottomCenter },
            targetScreenBottomCenterProvider: { _ in nil },
            screenBottomCenterProvider: { CGPoint(x: 640, y: 40) },
            levelProvider: { workflow.audioLevel }
        )

        controller.tick()

        XCTAssertEqual(controller.state.anchor?.point, CGPoint(x: 640, y: 40))
    }

    func testScreenBottomCenterModeKeepsTheInitialScreenAcrossTicks() {
        let (orchestrator, workflow) = makeOrchestratorWithWorkflow()
        var bottomCenter = CGPoint(x: 640, y: 40)
        let controller = RecordingOverlayController(
            orchestrator: orchestrator,
            modeProvider: { .screenBottomCenter },
            screenBottomCenterProvider: { bottomCenter },
            levelProvider: { workflow.audioLevel }
        )

        controller.tick()
        bottomCenter = CGPoint(x: 1920, y: 40)
        controller.tick()

        XCTAssertEqual(controller.state.anchor?.point, CGPoint(x: 640, y: 40), "must stay on the screen selected when recording started")
    }

    // MARK: - Bergung error (#151)

    func testBergungMessageEntersBergungErrorFromRecording() {
        let (orchestrator, _) = makeOrchestratorWithWorkflow()
        let controller = RecordingOverlayController(
            orchestrator: orchestrator,
            modeProvider: { .screenBottomCenter },
            anchorResolver: { self.anchor },
            levelProvider: { 0 }
        )
        controller.tick()
        XCTAssertEqual(controller.state.phase, .recording)

        orchestrator.reportBergung(message: "Engine-Fehler")
        controller.tick()

        XCTAssertEqual(controller.state.phase, .bergungError)
        XCTAssertEqual(controller.state.errorMessage, "Engine-Fehler")
    }

    func testBergungErrorPersistsThroughIdleObservations() {
        let (orchestrator, _) = makeOrchestratorWithWorkflow()
        let controller = RecordingOverlayController(
            orchestrator: orchestrator,
            modeProvider: { .screenBottomCenter },
            anchorResolver: { self.anchor },
            levelProvider: { 0 }
        )
        controller.tick()
        orchestrator.reportBergung(message: "boom")
        controller.tick()
        XCTAssertEqual(controller.state.phase, .bergungError)

        orchestrator.reset()
        controller.tick()
        controller.tick()

        XCTAssertEqual(controller.state.phase, .bergungError)
    }

    func testBergungErrorIsIgnoredOutsideRecording() {
        let (orchestrator, _) = makeOrchestratorWithWorkflow()
        let controller = RecordingOverlayController(
            orchestrator: orchestrator,
            modeProvider: { .screenBottomCenter },
            anchorResolver: { self.anchor },
            levelProvider: { 0 }
        )

        orchestrator.reportBergung(message: "too late")
        controller.tick()

        XCTAssertEqual(controller.state.phase, .recording)
    }

    // MARK: - Live transcript display via provider (#151)

    func testStructuredLiveTranscriptDisplayIsRelayedToState() {
        let (orchestrator, _) = makeOrchestratorWithWorkflow()
        let display = LiveTranscriptDisplay(finalText: "Fest.", volatileText: "flüchtig", maxLines: 3)
        let controller = RecordingOverlayController(
            orchestrator: orchestrator,
            modeProvider: { .screenBottomCenter },
            anchorResolver: { self.anchor },
            levelProvider: { 0 },
            liveTranscriptDisplayProvider: { display }
        )

        controller.tick()

        XCTAssertEqual(controller.state.liveTranscriptDisplay, display)
    }

    func testLiveTranscriptUpdatesWhileProcessing() {
        let (orchestrator, workflow) = makeOrchestratorWithWorkflow()
        var partial = "Hallo"
        let controller = RecordingOverlayController(
            orchestrator: orchestrator,
            modeProvider: { .screenBottomCenter },
            anchorResolver: { self.anchor },
            levelProvider: { 0 },
            liveTranscriptDisplayProvider: { LiveTranscriptDisplay(volatileText: partial) }
        )
        controller.tick()
        XCTAssertEqual(controller.state.phase, .recording)

        workflow.isRecording = false
        workflow.phase = .running("Wird verarbeitet ...")
        partial = "Hallo Welt"
        controller.tick()

        XCTAssertEqual(controller.state.phase, .processing)
        XCTAssertEqual(controller.state.liveTranscriptDisplay?.volatileText, "Hallo Welt")
    }

    // MARK: - Engine progress marker (#158 package 4)

    func testTranscriptionLagIsRelayedToStateWhileRecording() {
        let (orchestrator, _) = makeOrchestratorWithWorkflow()
        var lag: TimeInterval? = 2.5
        let controller = RecordingOverlayController(
            orchestrator: orchestrator,
            modeProvider: { .screenBottomCenter },
            anchorResolver: { self.anchor },
            levelProvider: { 0.5 },
            transcriptionLagProvider: { lag }
        )

        controller.tick()
        XCTAssertEqual(controller.state.transcriptionLag, 2.5)

        lag = 1.0
        controller.tick()
        XCTAssertEqual(controller.state.transcriptionLag, 1.0)
    }

    func testTranscriptionLagKeepsUpdatingWhileProcessing() {
        let (orchestrator, workflow) = makeOrchestratorWithWorkflow()
        var lag: TimeInterval? = 2.0
        let controller = RecordingOverlayController(
            orchestrator: orchestrator,
            modeProvider: { .screenBottomCenter },
            anchorResolver: { self.anchor },
            levelProvider: { workflow.audioLevel },
            transcriptionLagProvider: { lag }
        )
        controller.tick()
        XCTAssertEqual(controller.state.transcriptionLag, 2.0)

        workflow.isRecording = false
        workflow.phase = .running("Wird verarbeitet ...")
        lag = 0.5
        controller.tick()

        XCTAssertEqual(controller.state.phase, .processing)
        XCTAssertEqual(controller.state.transcriptionLag, 0.5)
    }

    func testTranscriptionLagStaysNilForWorkflowsWithoutLiveEngine() {
        let (orchestrator, _) = makeOrchestratorWithWorkflow()
        let controller = RecordingOverlayController(
            orchestrator: orchestrator,
            modeProvider: { .screenBottomCenter },
            anchorResolver: { self.anchor },
            levelProvider: { 0.5 }
        )

        controller.tick()

        XCTAssertEqual(controller.state.phase, .recording)
        XCTAssertNil(controller.state.transcriptionLag)
    }

    // MARK: - Paste error (#176)

    private func makePasteFailingOrchestrator(pasteTarget: PasteTarget) -> (WorkflowOrchestrator, FakeOverlayWorkflow) {
        var createdWorkflow: FakeOverlayWorkflow!
        let orchestrator = WorkflowOrchestrator(
            workflowFactory: { type in
                let workflow = FakeOverlayWorkflow(type: type)
                createdWorkflow = workflow
                return .workflow(workflow)
            },
            pasteAction: {},
            trustCheck: { _ in true },
            frontmostPidProvider: { 1 },
            writeToPasteboard: { _ in }
        )
        orchestrator.start(.transcription, source: .manual, pasteTarget: pasteTarget)
        return (orchestrator, createdWorkflow)
    }

    private func waitUntilPasteFailurePending(_ orchestrator: WorkflowOrchestrator, deadline: Date = Date().addingTimeInterval(5)) {
        guard orchestrator.pasteFailureMessage == nil else { return }
        guard Date() < deadline else {
            XCTFail("paste retry window did not exhaust within the timeout")
            return
        }
        let pollTick = expectation(description: "poll tick")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { pollTick.fulfill() }
        wait(for: [pollTick], timeout: 1)
        waitUntilPasteFailurePending(orchestrator, deadline: deadline)
    }

    func testPasteExhaustionShowsPersistentPasteErrorPill() {
        let target = makeFakePasteTarget(pid: 4242)
        let (orchestrator, workflow) = makePasteFailingOrchestrator(pasteTarget: target)
        let controller = RecordingOverlayController(
            orchestrator: orchestrator,
            modeProvider: { .screenBottomCenter },
            anchorResolver: { self.anchor },
            levelProvider: { workflow.audioLevel }
        )
        controller.tick()
        XCTAssertEqual(controller.state.phase, .recording)
        workflow.onOutput?("hello")

        waitUntilPasteFailurePending(orchestrator)
        controller.tick()

        XCTAssertEqual(controller.state.phase, .pasteError)
        XCTAssertEqual(controller.state.errorMessage, WorkflowOrchestrator.pasteRetryExhaustedMessage)
        XCTAssertEqual(controller.state.anchor, anchor)

        controller.tick()
        XCTAssertEqual(controller.state.phase, .pasteError, "must persist through repeated polling")

        controller.dismissPasteError()
        XCTAssertEqual(controller.state, .hidden)

        controller.tick()
        XCTAssertEqual(controller.state, .hidden, "the consumed failure must not reappear after dismissal")
    }

    func testPasteErrorPanelAcceptsMouseEventsSoItCanBeClosedManually() throws {
        let target = makeFakePasteTarget(pid: 4242)
        let (orchestrator, workflow) = makePasteFailingOrchestrator(pasteTarget: target)
        let controller = RecordingOverlayController(
            orchestrator: orchestrator,
            modeProvider: { .screenBottomCenter },
            anchorResolver: { self.anchor },
            levelProvider: { workflow.audioLevel }
        )
        controller.tick()
        workflow.onOutput?("hello")

        waitUntilPasteFailurePending(orchestrator)
        controller.tick()

        let panel = try XCTUnwrap(controller.debugPanel)
        XCTAssertFalse(panel.ignoresMouseEvents, "the paste-error pill must be clickable so it can be dismissed manually")
    }

    func testPasteExhaustionBouncesDockWhenPillDisabled() {
        let target = makeFakePasteTarget(pid: 4242)
        let (orchestrator, workflow) = makePasteFailingOrchestrator(pasteTarget: target)
        var attentionRequests = 0
        let controller = RecordingOverlayController(
            orchestrator: orchestrator,
            modeProvider: { .off },
            anchorResolver: { self.anchor },
            levelProvider: { workflow.audioLevel },
            requestUserAttention: { attentionRequests += 1 }
        )
        controller.tick()
        workflow.onOutput?("hello")

        waitUntilPasteFailurePending(orchestrator)
        controller.tick()

        XCTAssertEqual(attentionRequests, 1)
        XCTAssertEqual(controller.state, .hidden)

        controller.tick()
        XCTAssertEqual(attentionRequests, 1, "the dock bounce must fire exactly once per failure")
    }
}
