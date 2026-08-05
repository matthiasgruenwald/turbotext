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
        smoothingPass: (@Sendable (String) async -> String?)? = nil,
        smoothingBudget: Duration = .seconds(5),
        rewriteStage: RewriteStage? = nil,
        onBergung: ((String?) -> Void)? = nil,
        fileFallbackTranscriber: ((URL, TimeInterval) async throws -> String)? = nil,
        gracePeriod: Duration = .zero
    ) -> (LiveDictationWorkflow, LiveTranscriptionSession, FakeLiveRecorder) {
        let recorder = recorder ?? FakeLiveRecorder()
        let session = session ?? LiveTranscriptionSession()
        let pipeline = SpokenWorkflowPipeline(recorder: recorder)
        let workflow = LiveDictationWorkflow(
            type: .transcription,
            session: session,
            smoothingPass: smoothingPass,
            smoothingBudget: smoothingBudget,
            pipeline: pipeline,
            gracePeriod: gracePeriod,
            rewriteStage: rewriteStage,
            onBergung: onBergung,
            fileFallbackTranscriber: fileFallbackTranscriber
        )
        return (workflow, session, recorder)
    }

    private func feedSession(_ session: LiveTranscriptionSession, text: String) async {
        session.phase = .running
        session.finish()
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
        let session = LiveTranscriptionSession()
        await feedSession(session, text: "Hallo Welt")
        let (workflow, _, _) = makeWorkflow(session: session)
        workflow.start()

        let expectation = expectation(description: "output delivered")
        var output: String?
        workflow.onOutput = { text in
            output = text
            expectation.fulfill()
        }

        workflow.stop()
        await fulfillment(of: [expectation], timeout: 2)

        XCTAssertEqual(output, "Hallo Welt")
        XCTAssertEqual(workflow.phase, .done("Hallo Welt"))
    }

    func testStopWithEmptyTextShowsError() async {
        let (workflow, _, _) = makeWorkflow()
        workflow.start()

        let expectation = expectation(description: "error phase reached")
        workflow.onPhaseChange = { phase in
            if case .error = phase { expectation.fulfill() }
        }

        workflow.stop()
        await fulfillment(of: [expectation], timeout: 2)

        XCTAssertEqual(workflow.phase, .error("Keine Aufnahme erkannt."))
    }

    func testStopWithRewriteStageAppliesRewrittenOutcome() async {
        let session = LiveTranscriptionSession()
        await feedSession(session, text: "rohtext")
        let (workflow, _, _) = makeWorkflow(
            session: session,
            rewriteStage: RewriteStage { text in RewriteStepResult(text: text.uppercased(), completionLabel: "test") }
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
        XCTAssertEqual(workflow.phase, .done("ROHTEXT"))
        XCTAssertEqual(workflow.completionLabel, "test")
    }

    func testStopWithRewriteStageRejectsTranscriptBelowMinimumLength() async {
        let session = LiveTranscriptionSession()
        await feedSession(session, text: "a")
        var rewriteCalled = false
        let (workflow, _, _) = makeWorkflow(
            session: session,
            rewriteStage: RewriteStage { _ in
                rewriteCalled = true
                return RewriteStepResult(text: "ignored", completionLabel: nil)
            }
        )
        workflow.start()

        let expectation = expectation(description: "error phase reached")
        workflow.onPhaseChange = { phase in
            if case .error = phase { expectation.fulfill() }
        }

        workflow.stop()
        await fulfillment(of: [expectation], timeout: 2)

        XCTAssertEqual(workflow.phase, .error("Keine Aufnahme erkannt."))
        XCTAssertFalse(rewriteCalled)
    }

    func testStopWithRewriteStageInsertsShortTranscriptRawWithLabel() async {
        let session = LiveTranscriptionSession()
        await feedSession(session, text: "Nein")
        var rewriteCalled = false
        let (workflow, _, _) = makeWorkflow(
            session: session,
            rewriteStage: RewriteStage { _ in
                rewriteCalled = true
                return RewriteStepResult(text: "ignored", completionLabel: nil)
            }
        )
        workflow.start()

        let expectation = expectation(description: "output delivered")
        var output: String?
        workflow.onOutput = { text in
            output = text
            expectation.fulfill()
        }

        workflow.stop()
        await fulfillment(of: [expectation], timeout: 2)

        XCTAssertEqual(output, "Nein")
        XCTAssertEqual(workflow.phase, .done("Nein"))
        XCTAssertEqual(workflow.completionLabel, "Sehr kurze Eingabe – ohne Nachbearbeitung eingefügt")
        XCTAssertFalse(rewriteCalled)
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

    // MARK: - Drain (#159)

    func testStopWaitsForDrainAndUsesSessionText() async {
        let session = LiveTranscriptionSession()
        await feedSession(session, text: "Vollständiger Satz")
        var fallbackCalled = false
        let (workflow, _, _) = makeWorkflow(
            session: session,
            fileFallbackTranscriber: { _, _ in
                fallbackCalled = true
                return "Fallback"
            }
        )
        workflow.start()

        let expectation = expectation(description: "output delivered")
        var output: String?
        workflow.onOutput = { text in
            output = text
            expectation.fulfill()
        }

        workflow.stop()
        await fulfillment(of: [expectation], timeout: 2)

        XCTAssertEqual(output, "Vollständiger Satz")
        XCTAssertFalse(fallbackCalled, "drain war erfolgreich — Fallback darf nicht feuern")
    }

    func testStopFallsBackToFileTranscriptionWhenSessionFailed() async {
        let session = LiveTranscriptionSession()
        session.phase = .running
        let stream = AsyncThrowingStream<TranscriptionChunk, Error> { continuation in
            continuation.yield(TranscriptionChunk(text: "Teiltext", isFinal: true))
            continuation.finish(throwing: NSError(domain: "test", code: 1))
        }
        await session.runCollectingLoop(stream)

        let (workflow, _, _) = makeWorkflow(
            session: session,
            fileFallbackTranscriber: { _, _ in "Fallback-Text" }
        )
        workflow.start()

        let expectation = expectation(description: "output delivered")
        var output: String?
        workflow.onOutput = { text in
            output = text
            expectation.fulfill()
        }

        workflow.stop()
        await fulfillment(of: [expectation], timeout: 2)

        XCTAssertEqual(output, "Fallback-Text")
    }

    func testStopUsesCollectedTextWhenFallbackAlsoFails() async {
        let session = LiveTranscriptionSession()
        session.phase = .running
        let stream = AsyncThrowingStream<TranscriptionChunk, Error> { continuation in
            continuation.yield(TranscriptionChunk(text: "Geretteter Text", isFinal: true))
            continuation.finish(throwing: NSError(domain: "test", code: 1))
        }
        await session.runCollectingLoop(stream)

        let (workflow, _, _) = makeWorkflow(
            session: session,
            fileFallbackTranscriber: { _, _ in throw NSError(domain: "fallback", code: 1) }
        )
        workflow.start()

        let expectation = expectation(description: "output delivered")
        var output: String?
        workflow.onOutput = { text in
            output = text
            expectation.fulfill()
        }

        workflow.stop()
        await fulfillment(of: [expectation], timeout: 2)

        XCTAssertEqual(output, "Geretteter Text", "bei Fallback-Fehler muss der gesammelte Text verwendet werden")
    }

    // MARK: - Transkriptions-Deadline im Datei-Fallback (#177)

    func testFallbackTimeoutKeepsCollectedText() async {
        let session = LiveTranscriptionSession()
        session.phase = .running
        let stream = AsyncThrowingStream<TranscriptionChunk, Error> { continuation in
            continuation.yield(TranscriptionChunk(text: "Geretteter Text", isFinal: true))
            continuation.finish(throwing: NSError(domain: "test", code: 1))
        }
        await session.runCollectingLoop(stream)

        let (workflow, _, _) = makeWorkflow(
            session: session,
            fileFallbackTranscriber: { _, _ in throw AppleSpeechTranscriptionError.timedOut }
        )
        workflow.start()

        let expectation = expectation(description: "output delivered")
        var output: String?
        workflow.onOutput = { text in
            output = text
            expectation.fulfill()
        }

        workflow.stop()
        await fulfillment(of: [expectation], timeout: 2)

        XCTAssertEqual(output, "Geretteter Text", "nach Deadline-Ablauf des Fallbacks wird der gesammelte Text eingefügt")
    }

    func testFallbackTimeoutWithoutCollectedTextShowsNoRecordingError() async {
        let session = LiveTranscriptionSession()
        session.phase = .running
        let stream = AsyncThrowingStream<TranscriptionChunk, Error> { continuation in
            continuation.finish(throwing: NSError(domain: "test", code: 1))
        }
        await session.runCollectingLoop(stream)

        let (workflow, _, _) = makeWorkflow(
            session: session,
            fileFallbackTranscriber: { _, _ in throw AppleSpeechTranscriptionError.timedOut }
        )
        workflow.start()

        let expectation = expectation(description: "no-recording error reached")
        var sawNoRecordingError = false
        workflow.onPhaseChange = { phase in
            if case .error(let message) = phase, message == "Keine Aufnahme erkannt." {
                sawNoRecordingError = true
                expectation.fulfill()
            }
        }

        workflow.stop()
        await fulfillment(of: [expectation], timeout: 2)

        XCTAssertTrue(sawNoRecordingError)
    }

    func testBergungDoesNotFireDuringDrain() async {
        let session = LiveTranscriptionSession()
        await feedSession(session, text: "Text")
        var bergungFired = false
        let (workflow, _, _) = makeWorkflow(
            session: session,
            onBergung: { _ in bergungFired = true }
        )
        workflow.start()

        let expectation = expectation(description: "output delivered")
        workflow.onOutput = { _ in expectation.fulfill() }

        workflow.stop()
        await fulfillment(of: [expectation], timeout: 2)

        XCTAssertFalse(bergungFired, "Bergung darf während des Drains nicht feuern")
    }

    // MARK: - Glättung als Nachbearbeitung (#163)

    func testStopAppliesSmoothingPassBeforeOutput() async {
        let session = LiveTranscriptionSession()
        await feedSession(session, text: "roher satz")
        let (workflow, _, _) = makeWorkflow(
            session: session,
            smoothingPass: { text in "Geglättet: \(text)" }
        )
        workflow.start()

        let expectation = expectation(description: "output delivered")
        var output: String?
        workflow.onOutput = { text in
            output = text
            expectation.fulfill()
        }

        workflow.stop()
        await fulfillment(of: [expectation], timeout: 2)

        XCTAssertEqual(output, "Geglättet: roher satz")
    }

    func testSmoothingPassSeesFileFallbackText() async {
        let session = LiveTranscriptionSession()
        session.phase = .running
        let stream = AsyncThrowingStream<TranscriptionChunk, Error> { continuation in
            continuation.finish(throwing: NSError(domain: "test", code: 1))
        }
        await session.runCollectingLoop(stream)

        let (workflow, _, _) = makeWorkflow(
            session: session,
            smoothingPass: { text in "Geglättet: \(text)" },
            fileFallbackTranscriber: { _, _ in "Fallback-Text" }
        )
        workflow.start()

        let expectation = expectation(description: "output delivered")
        var output: String?
        workflow.onOutput = { text in
            output = text
            expectation.fulfill()
        }

        workflow.stop()
        await fulfillment(of: [expectation], timeout: 2)

        XCTAssertEqual(output, "Geglättet: Fallback-Text", "die Glättung greift auch auf dem Datei-Fallback-Pfad")
    }

    func testSmoothingBudgetExpiryDeliversRawText() async {
        let session = LiveTranscriptionSession()
        await feedSession(session, text: "roher satz")
        let (workflow, _, _) = makeWorkflow(
            session: session,
            smoothingPass: { text in
                try? await Task.sleep(for: .seconds(5))
                return "Geglättet: \(text)"
            },
            smoothingBudget: .milliseconds(50)
        )
        workflow.start()

        let expectation = expectation(description: "output delivered")
        var output: String?
        workflow.onOutput = { text in
            output = text
            expectation.fulfill()
        }

        workflow.stop()
        await fulfillment(of: [expectation], timeout: 2)

        XCTAssertEqual(output, "roher satz", "nach Ablauf des Budgets wird der Rohtext eingefügt")
    }

    func testSmoothingBudgetExpiryDoesNotWaitForUncancellablePass() async {
        let session = LiveTranscriptionSession()
        await feedSession(session, text: "roher satz")
        let (workflow, _, _) = makeWorkflow(
            session: session,
            smoothingPass: { text in
                // Models LanguageModelSession.respond: ignores cancellation and runs to completion.
                await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        continuation.resume(returning: "Geglättet: \(text)")
                    }
                }
            },
            smoothingBudget: .milliseconds(50)
        )
        workflow.start()

        let expectation = expectation(description: "output delivered")
        var output: String?
        workflow.onOutput = { text in
            output = text
            expectation.fulfill()
        }

        workflow.stop()
        await fulfillment(of: [expectation], timeout: 1)

        XCTAssertEqual(output, "roher satz", "ein nicht abbrechbarer Glättungs-Pass darf den Insert nicht über das Budget hinaus verzögern")
    }

    func testSmoothingNilResultKeepsRawText() async {
        let session = LiveTranscriptionSession()
        await feedSession(session, text: "roher satz")
        let (workflow, _, _) = makeWorkflow(
            session: session,
            smoothingPass: { _ in nil }
        )
        workflow.start()

        let expectation = expectation(description: "output delivered")
        var output: String?
        workflow.onOutput = { text in
            output = text
            expectation.fulfill()
        }

        workflow.stop()
        await fulfillment(of: [expectation], timeout: 2)

        XCTAssertEqual(output, "roher satz", "ein leeres Glättungsergebnis erhält den Rohtext")
    }

    // MARK: - Grace-Period (#160)

    func testStopKeepsRecordingAliveDuringGracePeriod() async {
        let recorder = FakeLiveRecorder()
        let (workflow, _, _) = makeWorkflow(recorder: recorder, gracePeriod: .milliseconds(50))
        workflow.start()

        workflow.stop()

        XCTAssertTrue(recorder.isRecording, "während der Grace-Period läuft die Aufnahme weiter")
        XCTAssertNotNil(recorder.onBuffer, "die Session wird während der Grace-Period weiter gefüttert")
        XCTAssertEqual(recorder.stopCount, 0)
        XCTAssertEqual(workflow.phase, .running("Aufnahme läuft ..."))

        try? await Task.sleep(for: .milliseconds(300))

        XCTAssertFalse(recorder.isRecording)
        XCTAssertEqual(recorder.stopCount, 1)
    }

    func testSecondStopDuringGraceFinalizesImmediately() async {
        let recorder = FakeLiveRecorder()
        let (workflow, _, _) = makeWorkflow(recorder: recorder, gracePeriod: .seconds(5))
        workflow.start()

        workflow.stop()
        XCTAssertTrue(recorder.isRecording)

        workflow.stop()

        XCTAssertFalse(recorder.isRecording, "zweiter Stopp bricht die Grace-Period sofort ab")
        XCTAssertEqual(recorder.stopCount, 1)

        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(recorder.stopCount, 1, "der gecancelte Grace-Task darf nicht nachfeuern")
    }

    func testResetDuringGraceCancelsGrace() async {
        let recorder = FakeLiveRecorder()
        let (workflow, _, _) = makeWorkflow(recorder: recorder, gracePeriod: .seconds(5))
        workflow.start()
        var outputCalled = false
        workflow.onOutput = { _ in outputCalled = true }

        workflow.stop()
        XCTAssertTrue(recorder.isRecording)

        workflow.reset()

        XCTAssertFalse(recorder.isRecording)
        XCTAssertEqual(workflow.phase, .idle)

        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(outputCalled)
        XCTAssertEqual(recorder.stopCount, 1, "nur reset() stoppt die Aufnahme, der Grace-Task feuert nicht nach")
    }

    func testBergungDuringGraceCancelsGraceAndBergsText() async {
        let session = LiveTranscriptionSession()
        let recorder = FakeLiveRecorder()
        let pipeline = SpokenWorkflowPipeline(recorder: recorder)
        var bergungFired = false
        let workflow = LiveDictationWorkflow(
            type: .transcription,
            session: session,
            pipeline: pipeline,
            gracePeriod: .seconds(5),
            onBergung: { _ in bergungFired = true }
        )
        var output: String?
        workflow.onOutput = { output = $0 }
        workflow.start()

        workflow.stop()
        XCTAssertTrue(recorder.isRecording, "Grace-Period hält die Aufnahme am Leben")

        session.phase = .running
        let stream = AsyncThrowingStream<TranscriptionChunk, Error> { continuation in
            continuation.yield(TranscriptionChunk(text: "Geretteter Text", isFinal: true))
            continuation.finish(throwing: NSError(domain: "test", code: 1))
        }
        await session.runCollectingLoop(stream)

        let expectation = expectation(description: "bergung processed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            expectation.fulfill()
        }
        await fulfillment(of: [expectation], timeout: 2)

        XCTAssertTrue(bergungFired)
        XCTAssertEqual(output, "Geretteter Text")
        XCTAssertFalse(recorder.isRecording)
        XCTAssertEqual(recorder.stopCount, 1, "Bergung stoppt sofort, der Grace-Task feuert nicht nach")
    }

    // MARK: - Rewrite workflows on the live path (#186)

    func testFileFallbackTextRunsThroughTextImproverStage() async {
        let session = LiveTranscriptionSession()
        session.phase = .running
        let stream = AsyncThrowingStream<TranscriptionChunk, Error> { continuation in
            continuation.yield(TranscriptionChunk(text: "Teiltext", isFinal: true))
            continuation.finish(throwing: NSError(domain: "test", code: 1))
        }
        await session.runCollectingLoop(stream)

        var improverInput: String?
        let (workflow, _, _) = makeWorkflow(
            session: session,
            rewriteStage: RewriteStage { text in
                improverInput = text
                return RewriteStepResult(text: "Verbessert: \(text)", completionLabel: "test")
            },
            fileFallbackTranscriber: { _, _ in "Fallback-Text" }
        )
        workflow.start()

        let expectation = expectation(description: "output delivered")
        var output: String?
        workflow.onOutput = { text in
            output = text
            expectation.fulfill()
        }

        workflow.stop()
        await fulfillment(of: [expectation], timeout: 2)

        XCTAssertEqual(improverInput, "Fallback-Text", "die Stage läuft auf dem Datei-Fallback-Ergebnis")
        XCTAssertEqual(output, "Verbessert: Fallback-Text")
        XCTAssertEqual(workflow.completionLabel, "test")
    }
}

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
