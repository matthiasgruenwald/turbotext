import XCTest
@testable import Turbotext

@available(macOS 26, *)
final class LiveTranscriptionSessionTests: XCTestCase {
    private struct TestEngineError: Error {}

    private final class SpySmoothing: LiveSmoothing, @unchecked Sendable {
        private(set) var calls: [(segment: String, context: String?)] = []
        var result: ((String) -> String?)?

        func smooth(segment: String, context: String?) async -> String? {
            calls.append((segment, context))
            return result?(segment) ?? segment
        }
    }

    private func makeSession(smoothing: any LiveSmoothing = PassthroughSmoothing()) -> LiveTranscriptionSession {
        let session = LiveTranscriptionSession(smoothing: smoothing)
        session.phase = .running
        return session
    }

    private func stream(
        _ chunks: [TranscriptionChunk],
        finishingWithError error: Error? = nil
    ) -> AsyncThrowingStream<TranscriptionChunk, Error> {
        AsyncThrowingStream { continuation in
            for chunk in chunks {
                continuation.yield(chunk)
            }
            if let error {
                continuation.finish(throwing: error)
            } else {
                continuation.finish()
            }
        }
    }

    func testFinalSegmentsFlowThroughSmoothingIntoCollector() async {
        let session = makeSession()
        session.finish()

        await session.runCollectingLoop(stream([
            TranscriptionChunk(text: "Hallo", isFinal: false),
            TranscriptionChunk(text: "Hallo Welt.", isFinal: true),
            TranscriptionChunk(text: "Zweiter Satz.", isFinal: true),
        ]))

        XCTAssertEqual(session.finalText, "Hallo Welt. Zweiter Satz.")
        XCTAssertEqual(session.volatileText, "")
        XCTAssertEqual(session.phase, .finished)
    }

    func testSmoothingResultReplacesRawSegment() async {
        let spy = SpySmoothing()
        spy.result = { $0.uppercased() }
        let session = makeSession(smoothing: spy)

        await session.runCollectingLoop(stream([
            TranscriptionChunk(text: "leiser text", isFinal: true),
        ]))

        XCTAssertEqual(session.finalText, "LEISER TEXT")
    }

    func testNilSmoothingResultFallsBackToRawSegment() async {
        let spy = SpySmoothing()
        spy.result = { _ in nil }
        let session = makeSession(smoothing: spy)

        await session.runCollectingLoop(stream([
            TranscriptionChunk(text: "rohes segment", isFinal: true),
        ]))

        XCTAssertEqual(session.finalText, "rohes segment")
    }

    func testSmoothingContextIsTailOfPreviousFinalSegment() async {
        let spy = SpySmoothing()
        let session = makeSession(smoothing: spy)

        await session.runCollectingLoop(stream([
            TranscriptionChunk(text: "Erster Satz.", isFinal: true),
            TranscriptionChunk(text: "Zweiter Satz.", isFinal: true),
        ]))

        XCTAssertEqual(spy.calls.count, 2)
        XCTAssertNil(spy.calls[0].context)
        XCTAssertEqual(spy.calls[1].context, "Erster Satz.")
    }

    func testVolatileChunkIsNotSmoothed() async {
        let spy = SpySmoothing()
        let session = makeSession(smoothing: spy)
        session.finish()

        await session.runCollectingLoop(stream([
            TranscriptionChunk(text: "unfertiger schwanz", isFinal: false),
        ]))

        XCTAssertTrue(spy.calls.isEmpty)
        XCTAssertEqual(session.volatileText, "unfertiger schwanz")
        XCTAssertEqual(session.phase, .finished)
    }

    func testEngineErrorAfterFinalSegmentsTriggersBergung() async {
        let session = makeSession()

        await session.runCollectingLoop(stream(
            [TranscriptionChunk(text: "Geretteter Satz.", isFinal: true)],
            finishingWithError: TestEngineError()
        ))

        guard case .failed(_, let isBergung) = session.phase else {
            return XCTFail("Erwartete .failed, bekam \(session.phase)")
        }
        XCTAssertTrue(isBergung)
        XCTAssertEqual(session.finalText, "Geretteter Satz.")
        XCTAssertEqual(session.collector.finalizedText, "Geretteter Satz.")
    }

    func testBergungDiscardsVolatileTail() async {
        let session = makeSession()

        await session.runCollectingLoop(stream(
            [
                TranscriptionChunk(text: "Fertig.", isFinal: true),
                TranscriptionChunk(text: "noch offen", isFinal: false),
            ],
            finishingWithError: TestEngineError()
        ))

        XCTAssertEqual(session.collector.finalizedText, "Fertig.")
        XCTAssertFalse(session.collector.finalizedText.contains("offen"))
    }

    func testEngineErrorWithoutFinalSegmentsIsNotBergung() async {
        let session = makeSession()

        await session.runCollectingLoop(stream(
            [TranscriptionChunk(text: "nur volatil", isFinal: false)],
            finishingWithError: TestEngineError()
        ))

        guard case .failed(_, let isBergung) = session.phase else {
            return XCTFail("Erwartete .failed, bekam \(session.phase)")
        }
        XCTAssertFalse(isBergung)
    }

    func testStreamEndWithoutFinishRequestTriggersBergung() async {
        let session = makeSession()

        await session.runCollectingLoop(stream([
            TranscriptionChunk(text: "Geretteter Satz.", isFinal: true),
        ]))

        guard case .failed(_, let isBergung) = session.phase else {
            return XCTFail("Erwartete .failed, bekam \(session.phase)")
        }
        XCTAssertTrue(isBergung)
        XCTAssertEqual(session.finalText, "Geretteter Satz.")
    }

    func testStreamEndWithoutFinishRequestAndWithoutFinalTextIsVisibleError() async {
        let session = makeSession()

        await session.runCollectingLoop(stream([
            TranscriptionChunk(text: "nur volatil", isFinal: false),
        ]))

        guard case .failed(_, let isBergung) = session.phase else {
            return XCTFail("Erwartete .failed, bekam \(session.phase)")
        }
        XCTAssertFalse(isBergung)
    }

    func testCancellationIsSilentWithoutBergung() async {
        let session = makeSession()

        await session.runCollectingLoop(stream(
            [TranscriptionChunk(text: "Gerettet.", isFinal: true)],
            finishingWithError: CancellationError()
        ))

        XCTAssertEqual(session.phase, .finished)
    }

    func testCancelMethodEndsInFinishedWithoutBergung() {
        let session = makeSession()

        session.cancel()

        XCTAssertEqual(session.phase, .finished)
    }

    func testErrorAfterCancelDoesNotOverrideFinished() async {
        let session = makeSession()
        session.cancel()

        await session.runCollectingLoop(stream(
            [TranscriptionChunk(text: "Text.", isFinal: true)],
            finishingWithError: TestEngineError()
        ))

        XCTAssertEqual(session.phase, .finished)
    }

    func testFinalizeTextAbsorbsVolatile() async {
        let session = makeSession()

        await session.runCollectingLoop(stream([
            TranscriptionChunk(text: "Fertig.", isFinal: true),
            TranscriptionChunk(text: "Schwanz", isFinal: false),
        ]))

        XCTAssertEqual(session.finalizeText(), "Fertig. Schwanz")
    }
}
