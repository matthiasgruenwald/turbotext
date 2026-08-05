import XCTest
@testable import Turbotext

@available(macOS 26, *)
@MainActor
final class LiveDictationWorkflowBergungTests: XCTestCase {

    func testBergungCallbackFiresOnSessionFailureWithRescuedText() async {
        let session = LiveTranscriptionSession()
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
        let session = LiveTranscriptionSession()
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

    func testBergungInsertsRawTextWithoutInvokingTheRewriteStage() async {
        let session = LiveTranscriptionSession()
        let recorder = FakeLiveRecorder()
        let pipeline = SpokenWorkflowPipeline(recorder: recorder)
        var rewriteCalled = false
        var bergungMessage: String??

        let workflow = LiveDictationWorkflow(
            type: .transcription,
            session: session,
            pipeline: pipeline,
            rewriteStage: RewriteStage { text in
                rewriteCalled = true
                return RewriteStepResult(text: text.uppercased(), completionLabel: nil)
            },
            onBergung: { bergungMessage = $0 }
        )
        var output: String?
        workflow.onOutput = { output = $0 }
        workflow.start()

        session.phase = .running
        let stream = AsyncThrowingStream<TranscriptionChunk, Error> { continuation in
            // Shorter than the stage's minimum length: only a stage-less raw insertion can deliver it.
            continuation.yield(TranscriptionChunk(text: "x", isFinal: true))
            continuation.finish(throwing: NSError(domain: "test", code: 1))
        }
        await session.runCollectingLoop(stream)

        let expectation = expectation(description: "bergung processed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            expectation.fulfill()
        }
        await fulfillment(of: [expectation], timeout: 2)

        XCTAssertNotNil(bergungMessage)
        XCTAssertEqual(output, "x", "geborgener Text wird roh und unabhängig von der Länge eingefügt")
        XCTAssertFalse(rewriteCalled, "die Bergung ruft die Rewrite-Stage nicht auf")
    }
}
