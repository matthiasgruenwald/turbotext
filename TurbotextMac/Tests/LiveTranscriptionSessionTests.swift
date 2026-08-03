import XCTest
@testable import Turbotext

@available(macOS 26, *)
final class LiveTranscriptionSessionTests: XCTestCase {
    private struct TestEngineError: Error {}

    private func makeSession() -> LiveTranscriptionSession {
        let session = LiveTranscriptionSession()
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

    func testFinalSegmentsFlowIntoCollector() async {
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

    func testVolatileChunkStaysVolatile() async {
        let session = makeSession()
        session.finish()

        await session.runCollectingLoop(stream([
            TranscriptionChunk(text: "unfertiger schwanz", isFinal: false),
        ]))

        XCTAssertEqual(session.volatileText, "unfertiger schwanz")
        XCTAssertEqual(session.finalText, "")
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
