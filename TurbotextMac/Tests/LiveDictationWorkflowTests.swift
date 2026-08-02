import AVFAudio
import XCTest
@testable import Turbotext

@MainActor
private final class FakeLiveRecorder: SpokenWorkflowRecording {
    var isRecording = false
    var recordingURL: URL? = URL(fileURLWithPath: "/tmp/fake-live.m4a")
    var errorMessage: String?
    var audioLevel: Float = 0
    var hasUsableSignal = true
    var lastRecordingDuration: TimeInterval = 1
    var inputFormat: AVAudioFormat? = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)
    var onBuffer: (@Sendable (AVAudioPCMBuffer) -> Void)?
    var startCount = 0
    var stopCount = 0

    func startRecording() {
        startCount += 1
        guard errorMessage == nil else { return }
        isRecording = true
    }

    func stopRecording() {
        stopCount += 1
        isRecording = false
    }

    func discardRecording() {
        recordingURL = nil
    }
}

@available(macOS 26, *)
@MainActor
final class LiveDictationWorkflowTests: XCTestCase {

    private func makeWorkflow(
        recorder: FakeLiveRecorder? = nil,
        session: LiveTranscriptionSession? = nil,
        rewrite: ((String) async throws -> RewriteStepResult)? = nil
    ) -> (LiveDictationWorkflow, LiveTranscriptionSession, FakeLiveRecorder) {
        let recorder = recorder ?? FakeLiveRecorder()
        let session = session ?? LiveTranscriptionSession(smoothing: PassthroughSmoothing())
        let pipeline = SpokenWorkflowPipeline(recorder: recorder)
        let workflow = LiveDictationWorkflow(
            type: .transcription,
            session: session,
            pipeline: pipeline,
            rewrite: rewrite
        )
        return (workflow, session, recorder)
    }

    private func feedSession(_ session: LiveTranscriptionSession, text: String) async {
        let stream = AsyncThrowingStream<TranscriptionChunk, Error> { continuation in
            continuation.yield(TranscriptionChunk(text: text, isFinal: true))
            continuation.finish()
        }
        await session.runCollectingLoop(stream)
    }

    func testStartBeginsRecordingAndSetsRunningPhase() {
        let (workflow, _, recorder) = makeWorkflow()

        workflow.start()

        XCTAssertEqual(workflow.phase, .running("Aufnahme läuft ..."))
        XCTAssertTrue(recorder.isRecording)
        XCTAssertEqual(recorder.startCount, 1)
    }

    func testStartFailsWithoutInputFormat() {
        let recorder = FakeLiveRecorder()
        recorder.inputFormat = nil
        let (workflow, _, _) = makeWorkflow(recorder: recorder)

        workflow.start()

        XCTAssertEqual(workflow.phase, .error("Audioformat nicht verfügbar."))
    }

    func testStartSurfacesRecorderError() {
        let recorder = FakeLiveRecorder()
        recorder.errorMessage = "Kein Mikrofon verfügbar."
        let (workflow, _, _) = makeWorkflow(recorder: recorder)

        workflow.start()

        XCTAssertEqual(workflow.phase, .error("Kein Mikrofon verfügbar."))
    }

    func testStopWithFinalizedTextCallsOnOutput() async {
        let session = LiveTranscriptionSession(smoothing: PassthroughSmoothing())
        await feedSession(session, text: "Hallo Welt")
        let (workflow, _, _) = makeWorkflow(session: session)
        workflow.start()
        var output: String?
        workflow.onOutput = { output = $0 }

        workflow.stop()

        XCTAssertEqual(output, "Hallo Welt")
        XCTAssertEqual(workflow.phase, .done("Hallo Welt"))
    }

    func testStopWithEmptyTextShowsError() {
        let (workflow, _, _) = makeWorkflow()
        workflow.start()
        var phaseChanges: [WorkflowPhase] = []
        workflow.onPhaseChange = { phaseChanges.append($0) }

        workflow.stop()

        XCTAssertEqual(workflow.phase, .error("Keine Aufnahme erkannt."))
    }

    func testStopWithRewriteAppliesRewriteStep() async {
        let session = LiveTranscriptionSession(smoothing: PassthroughSmoothing())
        await feedSession(session, text: "rohtext")
        let (workflow, _, _) = makeWorkflow(
            session: session,
            rewrite: { text in RewriteStepResult(text: text.uppercased(), completionLabel: "test") }
        )
        workflow.start()

        let expectation = expectation(description: "rewrite completes")
        var output: String?
        workflow.onOutput = { text in
            output = text
            expectation.fulfill()
        }

        workflow.stop()
        await fulfillment(of: [expectation], timeout: 2)

        XCTAssertEqual(output, "ROHTEXT")
        XCTAssertEqual(workflow.completionLabel, "test")
    }

    func testResetCancelsSilentlyWithoutOutput() {
        let (workflow, _, recorder) = makeWorkflow()
        workflow.start()
        var outputCalled = false
        workflow.onOutput = { _ in outputCalled = true }

        workflow.reset()

        XCTAssertFalse(outputCalled)
        XCTAssertEqual(workflow.phase, .idle)
        XCTAssertFalse(recorder.isRecording)
    }

    func testStopWhileNotRecordingCancelsToIdle() {
        let (workflow, _, _) = makeWorkflow()

        workflow.stop()

        XCTAssertEqual(workflow.phase, .idle)
    }

    func testStartSetsOnBufferOnRecorder() {
        let recorder = FakeLiveRecorder()
        let (workflow, _, _) = makeWorkflow(recorder: recorder)

        workflow.start()

        XCTAssertNotNil(recorder.onBuffer)
    }

    func testStopClearsOnBufferOnRecorder() {
        let recorder = FakeLiveRecorder()
        let (workflow, _, _) = makeWorkflow(recorder: recorder)
        workflow.start()

        workflow.stop()

        XCTAssertNil(recorder.onBuffer)
    }
}

@available(macOS 26, *)
@MainActor
final class LiveDictationWorkflowBergungTests: XCTestCase {

    func testBergungCallbackFiresOnSessionFailureWithRescuedText() async {
        let session = LiveTranscriptionSession(smoothing: PassthroughSmoothing())
        let recorder = FakeLiveRecorder()
        let pipeline = SpokenWorkflowPipeline(recorder: recorder)
        var bergungMessage: String??
        var output: String?

        let workflow = LiveDictationWorkflow(
            type: .transcription,
            session: session,
            pipeline: pipeline,
            onBergung: { bergungMessage = $0 }
        )
        workflow.onOutput = { output = $0 }
        workflow.start()

        let stream = AsyncThrowingStream<TranscriptionChunk, Error> { continuation in
            continuation.yield(TranscriptionChunk(text: "Geretteter Text", isFinal: true))
            continuation.finish(throwing: NSError(domain: "test", code: 1))
        }
        session.phase = .running
        await session.runCollectingLoop(stream)

        let expectation = expectation(description: "bergung processed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            expectation.fulfill()
        }
        await fulfillment(of: [expectation], timeout: 2)

        XCTAssertNotNil(bergungMessage)
        XCTAssertEqual(output, "Geretteter Text")
    }

    func testStreamEndWithoutFinishRequestStopsRecordingAndBergsImmediately() async {
        let session = LiveTranscriptionSession(smoothing: PassthroughSmoothing())
        let recorder = FakeLiveRecorder()
        let pipeline = SpokenWorkflowPipeline(recorder: recorder)
        var bergungMessage: String??
        var output: String?

        let workflow = LiveDictationWorkflow(
            type: .transcription,
            session: session,
            pipeline: pipeline,
            onBergung: { bergungMessage = $0 }
        )
        workflow.onOutput = { output = $0 }
        workflow.start()
        XCTAssertTrue(recorder.isRecording)

        session.phase = .running
        let stream = AsyncThrowingStream<TranscriptionChunk, Error> { continuation in
            continuation.yield(TranscriptionChunk(text: "Geretteter Text", isFinal: true))
            continuation.finish()
        }
        await session.runCollectingLoop(stream)

        let expectation = expectation(description: "bergung processed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            expectation.fulfill()
        }
        await fulfillment(of: [expectation], timeout: 2)

        XCTAssertFalse(recorder.isRecording, "Aufnahme muss sofort stoppen, nicht erst beim Nutzer-Stop")
        XCTAssertNotNil(bergungMessage)
        XCTAssertEqual(output, "Geretteter Text")
    }
}
