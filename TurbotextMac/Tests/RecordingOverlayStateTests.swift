import XCTest
@testable import Turbotext

final class RecordingOverlayStateTests: XCTestCase {
    private let anchor = RecordingOverlayAnchor(point: CGPoint(x: 10, y: 20), source: .textCursor)
    private let mouseAnchor = RecordingOverlayAnchor(point: CGPoint(x: 1, y: 1), source: .mousePointer)

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
}
