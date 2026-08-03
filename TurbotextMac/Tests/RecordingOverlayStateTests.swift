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

    func testSilenceHintIsSuppressedWhileLiveTranscriptHasVolatileText() {
        var state = RecordingOverlayState(phase: .recording, anchor: anchor, levelHistory: [])
            .receivingLiveTranscript(LiveTranscriptDisplay(volatileText: "Hallo"))
        for _ in 0..<60 {
            state = state.receivingLevel(0, elapsed: 0.1)
        }

        XCTAssertFalse(state.showsSilenceHint)
    }

    func testSilenceHintIsSuppressedWhileLiveTranscriptHasFinalText() {
        var state = RecordingOverlayState(phase: .recording, anchor: anchor, levelHistory: [])
            .receivingLiveTranscript(LiveTranscriptDisplay(finalText: "Bereits fest."))
        for _ in 0..<60 {
            state = state.receivingLevel(0, elapsed: 0.1)
        }

        XCTAssertFalse(state.showsSilenceHint)
    }

    func testSilenceHintAppearsDespiteEmptyLiveTranscriptDisplay() {
        var state = RecordingOverlayState(phase: .recording, anchor: anchor, levelHistory: [])
            .receivingLiveTranscript(LiveTranscriptDisplay())
        for _ in 0..<50 {
            state = state.receivingLevel(0, elapsed: 0.1)
        }

        XCTAssertTrue(state.showsSilenceHint)
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

    // MARK: - Live transcript display (#150)

    func testLiveTranscriptDisplayUpdatesWhileRecording() {
        let recording = RecordingOverlayState.hidden.applying(menuBarStatus: .recording(.transcription)) { self.anchor }
        let updated = recording.receivingLiveTranscript(LiveTranscriptDisplay(volatileText: "Hallo"))

        XCTAssertEqual(updated.liveTranscriptDisplay?.volatileText, "Hallo")
        XCTAssertEqual(updated.phase, .recording)
    }

    func testLiveTranscriptDisplayCarriesAllFields() {
        let recording = RecordingOverlayState(phase: .recording, anchor: anchor, levelHistory: [])
        let display = LiveTranscriptDisplay(
            finalText: "Fester Satz.", volatileText: "schwankt", isSmoothingActive: true, maxLines: 3
        )

        let updated = recording.receivingLiveTranscript(display)

        XCTAssertEqual(updated.liveTranscriptDisplay, display)
    }

    func testIdenticalLiveTranscriptDisplayIsANoOp() {
        let recording = RecordingOverlayState(phase: .recording, anchor: anchor, levelHistory: [])
        let display = LiveTranscriptDisplay(finalText: "A", volatileText: "B")

        let updated = recording.receivingLiveTranscript(display)
        let again = updated.receivingLiveTranscript(display)

        XCTAssertEqual(again, updated)
    }

    func testLiveTranscriptDisplayIsIgnoredOutsideRecording() {
        let hidden = RecordingOverlayState.hidden
        XCTAssertEqual(hidden.receivingLiveTranscript(LiveTranscriptDisplay(volatileText: "Hallo")), hidden)
    }

    func testLiveTranscriptDisplayUpdatesWhileProcessing() {
        let processing = RecordingOverlayState(phase: .processing, anchor: anchor, levelHistory: [])
        let updated = processing.receivingLiveTranscript(LiveTranscriptDisplay(finalText: "Nachlauf"))

        XCTAssertEqual(updated.liveTranscriptDisplay?.finalText, "Nachlauf")
        XCTAssertEqual(updated.phase, .processing)
    }

    func testLiveTranscriptDisplaySurvivesTransitionToProcessing() {
        let recording = RecordingOverlayState(phase: .recording, anchor: anchor, levelHistory: [])
            .receivingLiveTranscript(LiveTranscriptDisplay(finalText: "Satz", volatileText: "Ende"))

        let processing = recording.applying(menuBarStatus: .processing(.transcription)) { self.anchor }

        XCTAssertEqual(processing.phase, .processing)
        XCTAssertEqual(processing.liveTranscriptDisplay?.finalText, "Satz")
        XCTAssertEqual(processing.liveTranscriptDisplay?.volatileText, "Ende")
    }

    func testLiveTranscriptDisplaySurvivesLevelUpdates() {
        let recording = RecordingOverlayState(phase: .recording, anchor: anchor, levelHistory: [])
            .receivingLiveTranscript(LiveTranscriptDisplay(volatileText: "Hallo"))

        let updated = recording.receivingLevel(0.6, elapsed: 0.1)

        XCTAssertEqual(updated.liveTranscriptDisplay?.volatileText, "Hallo")
    }

    func testLiveTranscriptDisplayResetsOnNewRecording() {
        let firstRecording = RecordingOverlayState.hidden
            .applying(menuBarStatus: .recording(.transcription)) { self.anchor }
            .receivingLiveTranscript(LiveTranscriptDisplay(finalText: "Alter Text"))
        let processing = firstRecording.applying(menuBarStatus: .processing(.transcription)) { self.anchor }
        let idle = processing.applying(menuBarStatus: .idle) { self.anchor }
        let secondRecording = idle.applying(menuBarStatus: .recording(.transcription)) { self.anchor }

        XCTAssertNil(secondRecording.liveTranscriptDisplay)
    }

    func testLiveTranscriptDisplayTextJoinsFinalAndVolatile() {
        XCTAssertEqual(LiveTranscriptDisplay(finalText: "a", volatileText: "b").displayText, "a b")
        XCTAssertEqual(LiveTranscriptDisplay(finalText: "a").displayText, "a")
        XCTAssertEqual(LiveTranscriptDisplay(volatileText: "b").displayText, "b")
        XCTAssertEqual(LiveTranscriptDisplay().displayText, "")
    }

    func testLiveTranscriptDisplayIsEmptyOnlyWithoutAnyText() {
        XCTAssertTrue(LiveTranscriptDisplay().isEmpty)
        XCTAssertFalse(LiveTranscriptDisplay(finalText: "a").isEmpty)
        XCTAssertFalse(LiveTranscriptDisplay(volatileText: "b").isEmpty)
    }

    // MARK: - Bergung error (#150)

    func testBergungErrorEntersFromRecordingWithMessage() {
        let recording = RecordingOverlayState.hidden.applying(menuBarStatus: .recording(.transcription)) { self.anchor }

        let bergung = recording.enteringBergungError(message: "Engine-Fehler")

        XCTAssertEqual(bergung.phase, .bergungError)
        XCTAssertEqual(bergung.anchor, anchor)
        XCTAssertEqual(bergung.errorMessage, "Engine-Fehler")
    }

    func testBergungErrorIsOnlyEnteredFromRecording() {
        XCTAssertEqual(RecordingOverlayState.hidden.enteringBergungError(message: "x"), .hidden)

        let processing = RecordingOverlayState(phase: .processing, anchor: anchor, levelHistory: [])
        XCTAssertEqual(processing.enteringBergungError(message: "x"), processing)
    }

    func testBergungErrorNeverAutoDismisses() {
        let recording = RecordingOverlayState.hidden.applying(menuBarStatus: .recording(.transcription)) { self.anchor }
        var state = recording.enteringBergungError(message: "boom")

        for _ in 0..<200 {
            state = state.advancingError(by: 0.1)
        }

        XCTAssertEqual(state.phase, .bergungError)
        XCTAssertEqual(state.errorMessage, "boom")
    }

    func testBergungErrorSurvivesRepeatedIdleAndErrorObservations() {
        let recording = RecordingOverlayState.hidden.applying(menuBarStatus: .recording(.transcription)) { self.anchor }
        let bergung = recording.enteringBergungError(message: "boom")

        let afterIdle = bergung.applying(menuBarStatus: .idle) { self.anchor }
        let afterError = afterIdle.applying(
            menuBarStatus: .error(.transcription),
            resolveAnchor: { self.anchor },
            resolveErrorMessage: { "boom" }
        )

        XCTAssertEqual(afterIdle.phase, .bergungError)
        XCTAssertEqual(afterError.phase, .bergungError)
        XCTAssertEqual(afterError.errorMessage, "boom")
    }

    func testBergungErrorCanBeDismissedManually() {
        let recording = RecordingOverlayState.hidden.applying(menuBarStatus: .recording(.transcription)) { self.anchor }
        let bergung = recording.enteringBergungError(message: "boom")

        XCTAssertEqual(bergung.dismissingBergungError(), .hidden)
    }

    func testDismissingBergungErrorIsIgnoredOutsideBergungPhase() {
        let recording = RecordingOverlayState.hidden.applying(menuBarStatus: .recording(.transcription)) { self.anchor }

        XCTAssertEqual(recording.dismissingBergungError(), recording)
    }

    func testNewRecordingOverridesBergungError() {
        let recording = RecordingOverlayState.hidden.applying(menuBarStatus: .recording(.transcription)) { self.anchor }
        let bergung = recording.enteringBergungError(message: "boom")

        let recovered = bergung.applying(menuBarStatus: .recording(.transcription)) { self.mouseAnchor }

        XCTAssertEqual(recovered.phase, .recording)
        XCTAssertEqual(recovered.anchor, mouseAnchor)
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

    // MARK: - Signal received (#132)

    func testSignalReceivedFlipsTrueOnUsableLevel() {
        let recording = RecordingOverlayState(phase: .recording, anchor: anchor, levelHistory: [])
        XCTAssertFalse(recording.signalReceived)

        let updated = recording.receivingLevel(0.6, elapsed: 0.1)
        XCTAssertTrue(updated.signalReceived)
    }

    func testSignalReceivedStaysTrueForRestOfRecording() {
        var state = RecordingOverlayState(phase: .recording, anchor: anchor, levelHistory: [])
        state = state.receivingLevel(0.6, elapsed: 0.1)
        state = state.receivingLevel(0.0, elapsed: 0.1)
        state = state.receivingLevel(0.0, elapsed: 0.1)

        XCTAssertTrue(state.signalReceived)
    }

    func testSignalReceivedResetsOnNewRecording() {
        let firstRecording = RecordingOverlayState(phase: .recording, anchor: anchor, levelHistory: [])
            .receivingLevel(0.6, elapsed: 0.1)
        let processing = firstRecording.applying(menuBarStatus: .processing(.transcription)) { self.anchor }
        let idle = processing.applying(menuBarStatus: .idle) { self.anchor }
        let secondRecording = idle.applying(menuBarStatus: .recording(.transcription)) { self.anchor }

        XCTAssertFalse(secondRecording.signalReceived)
    }

    func testSignalReceivedStaysFalseWithoutUsableLevel() {
        var state = RecordingOverlayState(phase: .recording, anchor: anchor, levelHistory: [])
        for _ in 0..<10 {
            state = state.receivingLevel(0.01, elapsed: 0.1)
        }

        XCTAssertFalse(state.signalReceived)
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
