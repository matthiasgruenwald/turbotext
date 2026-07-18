import XCTest
@testable import Turbotext

final class RecordingOverlayStateTests: XCTestCase {
    private let anchor = RecordingOverlayAnchor(point: CGPoint(x: 10, y: 20), source: .screenBottomCenter)
    private let mouseAnchor = RecordingOverlayAnchor(point: CGPoint(x: 1, y: 1), source: .screenBottomCenter)

    func testIdleStaysHidden() {
        let state = RecordingOverlayState.hidden.applying(menuBarStatus: .idle) { self.anchor }
        XCTAssertEqual(state, .hidden)
    }

    func testRecordingStatusFromHiddenComputesAnchorOnce() {
        var resolveCount = 0
        let state = RecordingOverlayState.hidden.applying(menuBarStatus: .recording(.transcription)) {
            resolveCount += 1
            return self.anchor
        }

        XCTAssertEqual(state.phase, .recording)
        XCTAssertEqual(state.anchor, anchor)
        XCTAssertEqual(resolveCount, 1)
    }

    func testAnchorFreezesForRestOfRecordingLifetime() {
        let recording = RecordingOverlayState.hidden.applying(menuBarStatus: .recording(.transcription)) { self.anchor }

        // A repeated .recording observation (e.g. from polling) must not re-resolve the anchor,
        // even if focus moved and would now yield a different anchor.
        let stillRecording = recording.applying(menuBarStatus: .recording(.transcription)) { self.mouseAnchor }

        XCTAssertEqual(stillRecording.anchor, anchor)
    }

    func testProcessingKeepsAnchorAndHistoryVisible() {
        let recording = RecordingOverlayState.hidden
            .applying(menuBarStatus: .recording(.transcription)) { self.anchor }
            .receivingLevel(0.6)

        let processing = recording.applying(menuBarStatus: .processing(.transcription)) { self.anchor }

        XCTAssertEqual(processing.phase, .processing)
        XCTAssertEqual(processing.anchor, anchor)
        XCTAssertEqual(processing.levelHistory, [0.6])
    }

    func testSuccessKeepsOverlayVisibleUntilCleanup() {
        let recording = RecordingOverlayState.hidden.applying(menuBarStatus: .recording(.transcription)) { self.anchor }
        let success = recording.applying(menuBarStatus: .success(.transcription)) { self.anchor }

        XCTAssertEqual(success.phase, .processing)
    }

    func testIdleAfterOutputHidesOverlay() {
        let recording = RecordingOverlayState.hidden.applying(menuBarStatus: .recording(.transcription)) { self.anchor }
        let success = recording.applying(menuBarStatus: .success(.transcription)) { self.anchor }
        let idle = success.applying(menuBarStatus: .idle) { self.anchor }

        XCTAssertEqual(idle, .hidden)
    }

    func testErrorHidesOverlay() {
        let recording = RecordingOverlayState.hidden.applying(menuBarStatus: .recording(.transcription)) { self.anchor }
        let errored = recording.applying(menuBarStatus: .error(.transcription)) { self.anchor }

        XCTAssertEqual(errored, .hidden)
    }

    func testReceivingLevelIsIgnoredOutsideRecording() {
        let processing = RecordingOverlayState(phase: .processing, anchor: anchor, levelHistory: [])
        XCTAssertEqual(processing.receivingLevel(0.9), processing)
    }

    func testReceivingLevelClampsToUnitRange() {
        let recording = RecordingOverlayState(phase: .recording, anchor: anchor, levelHistory: [])
        let updated = recording.receivingLevel(-1).receivingLevel(5)
        XCTAssertEqual(updated.levelHistory, [0, 1])
    }

    func testLevelHistoryKeepsRoughlyThirtySamples() {
        var state = RecordingOverlayState(phase: .recording, anchor: anchor, levelHistory: [])
        for i in 0..<50 {
            state = state.receivingLevel(Float(i) / 50)
        }
        XCTAssertEqual(state.levelHistory.count, RecordingOverlayState.levelHistoryLimit)
        XCTAssertEqual(RecordingOverlayState.levelHistoryLimit, 30)
    }

    // MARK: - Silence hint

    func testSilenceHintAppearsAfterFiveSecondsWithoutUsableSignal() {
        var state = RecordingOverlayState(phase: .recording, anchor: anchor, levelHistory: [])
        for _ in 0..<49 {
            state = state.receivingLevel(0, elapsed: 0.1)
        }
        XCTAssertFalse(state.showsSilenceHint, "must not fire before the full 5s window elapses")

        state = state.receivingLevel(0, elapsed: 0.1)
        XCTAssertTrue(state.showsSilenceHint)
    }

    func testSilenceHintClearsOnceUsableSignalReturns() {
        var state = RecordingOverlayState(phase: .recording, anchor: anchor, levelHistory: [])
        for _ in 0..<50 {
            state = state.receivingLevel(0, elapsed: 0.1)
        }
        XCTAssertTrue(state.showsSilenceHint)

        state = state.receivingLevel(0.6, elapsed: 0.1)
        XCTAssertFalse(state.showsSilenceHint)
    }

    func testRecordingContinuesWhileSilenceHintIsShown() {
        var state = RecordingOverlayState(phase: .recording, anchor: anchor, levelHistory: [])
        for _ in 0..<50 {
            state = state.receivingLevel(0, elapsed: 0.1)
        }
        XCTAssertEqual(state.phase, .recording, "the hint is an overlay-only indicator; recording itself is unaffected")
    }

    // MARK: - Known start errors

    func testKnownStartErrorFromHiddenSurfacesInErrorPhaseWithMessage() {
        let state = RecordingOverlayState.hidden.applying(
            menuBarStatus: .error(.transcription),
            resolveAnchor: { self.anchor },
            resolveErrorMessage: { "Kein Mikrofon verfügbar." }
        )

        XCTAssertEqual(state.phase, .error)
        XCTAssertEqual(state.anchor, anchor)
        XCTAssertEqual(state.errorMessage, "Kein Mikrofon verfügbar.")
    }

    func testErrorAutoDismissesAfterFiveSeconds() {
        var state = RecordingOverlayState.hidden.applying(
            menuBarStatus: .error(.transcription),
            resolveAnchor: { self.anchor },
            resolveErrorMessage: { "boom" }
        )
        for _ in 0..<49 {
            state = state.advancingError(by: 0.1)
        }
        XCTAssertEqual(state.phase, .error, "must stay visible for the full 5s")

        state = state.advancingError(by: 0.1)
        XCTAssertEqual(state, .hidden)
    }

    /// Regression: `WorkflowOrchestrator.menuBarStatus` keeps reporting the same
    /// `.error` value on every poll (nothing clears it until the orchestrator's own
    /// ~1.6s internal reset). Re-applying that unchanged observation must not hide
    /// the pill — only `advancingError`'s own 5s countdown may do that.
    func testRepeatedIdenticalErrorObservationDoesNotHideThePill() {
        let errored = RecordingOverlayState.hidden.applying(
            menuBarStatus: .error(.transcription),
            resolveAnchor: { self.anchor },
            resolveErrorMessage: { "boom" }
        )

        let stillErrored = errored.applying(
            menuBarStatus: .error(.transcription),
            resolveAnchor: { self.anchor },
            resolveErrorMessage: { "boom" }
        )

        XCTAssertEqual(stillErrored.phase, .error)
        XCTAssertEqual(stillErrored.errorMessage, "boom")
    }

    /// Regression: the orchestrator resets `menuBarStatus` to `.idle` on its own after
    /// ~1.6s (well before the pill's 5s window) once a hotkey-background launch's
    /// active workflow is cleared. That internal reset must not hide the error early.
    func testIdleObservationWhileErrorIsShowingDoesNotHideItEarly() {
        let errored = RecordingOverlayState.hidden.applying(
            menuBarStatus: .error(.transcription),
            resolveAnchor: { self.anchor },
            resolveErrorMessage: { "boom" }
        )

        let stillErrored = errored.applying(menuBarStatus: .idle) { self.anchor }

        XCTAssertEqual(stillErrored.phase, .error)
        XCTAssertEqual(stillErrored.errorMessage, "boom")
    }

    func testSuccessfulRetryOverridesAVisibleErrorImmediately() {
        let errored = RecordingOverlayState.hidden.applying(
            menuBarStatus: .error(.transcription),
            resolveAnchor: { self.anchor },
            resolveErrorMessage: { "boom" }
        )

        let recovered = errored.applying(menuBarStatus: .recording(.transcription)) { self.mouseAnchor }

        XCTAssertEqual(recovered.phase, .recording)
        XCTAssertEqual(recovered.anchor, mouseAnchor)
    }

    func testErrorCanBeDismissedManuallyBeforeTheTimerElapses() {
        let errored = RecordingOverlayState.hidden.applying(
            menuBarStatus: .error(.transcription),
            resolveAnchor: { self.anchor },
            resolveErrorMessage: { "boom" }
        )

        XCTAssertEqual(errored.dismissingError(), .hidden)
    }

    // MARK: - Partial transcript (#128)

    func testPartialTranscriptUpdatesWhileRecording() {
        let recording = RecordingOverlayState.hidden.applying(menuBarStatus: .recording(.transcription)) { self.anchor }
        let updated = recording.receivingPartialTranscript("Hallo")

        XCTAssertEqual(updated.partialTranscript, "Hallo")
        XCTAssertEqual(updated.phase, .recording)
    }

    func testPartialTranscriptIsIgnoredOutsideRecording() {
        let processing = RecordingOverlayState(phase: .processing, anchor: anchor, levelHistory: [])
        XCTAssertEqual(processing.receivingPartialTranscript("Hallo"), processing)
    }

    func testPartialTranscriptResetsOnNewRecording() {
        let firstRecording = RecordingOverlayState.hidden
            .applying(menuBarStatus: .recording(.transcription)) { self.anchor }
            .receivingPartialTranscript("Alter Text")
        let processing = firstRecording.applying(menuBarStatus: .processing(.transcription)) { self.anchor }
        let idle = processing.applying(menuBarStatus: .idle) { self.anchor }
        let secondRecording = idle.applying(menuBarStatus: .recording(.transcription)) { self.anchor }

        XCTAssertNil(secondRecording.partialTranscript)
    }

    // MARK: - Processing label (#128)

    func testProcessingLabelIsResolvedOnceEnteringProcessing() {
        var resolveCount = 0
        let recording = RecordingOverlayState.hidden.applying(menuBarStatus: .recording(.transcription)) { self.anchor }
        let processing = recording.applying(
            menuBarStatus: .processing(.transcription),
            resolveAnchor: { self.anchor },
            resolveProcessingLabel: {
                resolveCount += 1
                return "Nachbearbeitung läuft – lokal auf diesem Mac"
            }
        )
        let stillProcessing = processing.applying(
            menuBarStatus: .processing(.transcription),
            resolveAnchor: { self.anchor },
            resolveProcessingLabel: {
                resolveCount += 1
                return "should not be used"
            }
        )

        XCTAssertEqual(processing.processingLabel, "Nachbearbeitung läuft – lokal auf diesem Mac")
        XCTAssertEqual(stillProcessing.processingLabel, "Nachbearbeitung läuft – lokal auf diesem Mac")
        XCTAssertEqual(resolveCount, 1)
    }

    // MARK: - Completion label (#128)

    func testIdleAfterProcessingWithCompletionLabelShowsCompletionPhase() {
        let recording = RecordingOverlayState.hidden.applying(menuBarStatus: .recording(.transcription)) { self.anchor }
        let processing = recording.applying(menuBarStatus: .processing(.transcription)) { self.anchor }
        let completion = processing.applying(
            menuBarStatus: .idle,
            resolveAnchor: { self.anchor },
            resolveCompletionLabel: { "Text lokal verbessert · Apple Foundation Models" }
        )

        XCTAssertEqual(completion.phase, .completion)
        XCTAssertEqual(completion.completionLabel, "Text lokal verbessert · Apple Foundation Models")
    }

    func testIdleAfterProcessingWithoutCompletionLabelHidesAsBefore() {
        let recording = RecordingOverlayState.hidden.applying(menuBarStatus: .recording(.transcription)) { self.anchor }
        let processing = recording.applying(menuBarStatus: .processing(.transcription)) { self.anchor }
        let idle = processing.applying(menuBarStatus: .idle) { self.anchor }

        XCTAssertEqual(idle, .hidden)
    }

    func testCompletionAutoDismissesAfterThreeSeconds() {
        var state = RecordingOverlayState(phase: .completion, anchor: anchor, levelHistory: [], completionLabel: "done")
        for _ in 0..<29 {
            state = state.advancingCompletion(by: 0.1)
        }
        XCTAssertEqual(state.phase, .completion, "must stay visible for the full 3s")

        state = state.advancingCompletion(by: 0.1)
        XCTAssertEqual(state, .hidden)
    }

    func testRepeatedIdleObservationDoesNotHideCompletionEarly() {
        let completion = RecordingOverlayState(phase: .completion, anchor: anchor, levelHistory: [], completionLabel: "done")
        let stillCompletion = completion.applying(menuBarStatus: .idle) { self.anchor }

        XCTAssertEqual(stillCompletion.phase, .completion)
        XCTAssertEqual(stillCompletion.completionLabel, "done")
    }

    func testCompletionCanBeDismissedManuallyBeforeTheTimerElapses() {
        let completion = RecordingOverlayState(phase: .completion, anchor: anchor, levelHistory: [], completionLabel: "done")
        XCTAssertEqual(completion.dismissingCompletion(), .hidden)
    }

    func testErrorMidRecordingStillHidesImmediately() {
        // Errors after recording visibly began (e.g. a later transcription failure) are
        // out of this issue's scope and keep the pre-existing hide-immediately behavior.
        let recording = RecordingOverlayState.hidden.applying(menuBarStatus: .recording(.transcription)) { self.anchor }
        let errored = recording.applying(
            menuBarStatus: .error(.transcription),
            resolveAnchor: { self.anchor },
            resolveErrorMessage: { "boom" }
        )

        XCTAssertEqual(errored, .hidden)
    }
}
