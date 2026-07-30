import XCTest
@testable import Turbotext

final class LiveTranscriptCollectorTests: XCTestCase {
    func testEmptyCollectorHasEmptyTexts() {
        let collector = LiveTranscriptCollector()
        XCTAssertEqual(collector.finalText, "")
        XCTAssertEqual(collector.volatileText, "")
        XCTAssertEqual(collector.displayText, "")
        XCTAssertEqual(collector.finalizedText, "")
    }

    func testVolatileResultSetsVolatileText() {
        var collector = LiveTranscriptCollector()
        collector.apply(text: "Hallo Welt", isFinal: false)
        XCTAssertEqual(collector.volatileText, "Hallo Welt")
        XCTAssertEqual(collector.finalText, "")
        XCTAssertEqual(collector.displayText, "Hallo Welt")
    }

    func testVolatileResultReplacesPreviousVolatile() {
        var collector = LiveTranscriptCollector()
        collector.apply(text: "Hallo", isFinal: false)
        collector.apply(text: "Hallo Welt", isFinal: false)
        XCTAssertEqual(collector.volatileText, "Hallo Welt")
        XCTAssertEqual(collector.displayText, "Hallo Welt")
    }

    func testFinalResultAppendsNotOverwrites() {
        var collector = LiveTranscriptCollector()
        collector.apply(text: "Erster Satz.", isFinal: true)
        collector.apply(text: "Zweiter Satz.", isFinal: true)
        XCTAssertEqual(collector.finalText, "Erster Satz. Zweiter Satz.")
    }

    func testFinalResultClearsVolatile() {
        var collector = LiveTranscriptCollector()
        collector.apply(text: "Unfertiger Text", isFinal: false)
        collector.apply(text: "Fertiger Text.", isFinal: true)
        XCTAssertEqual(collector.volatileText, "")
        XCTAssertEqual(collector.finalText, "Fertiger Text.")
    }

    func testDisplayTextCombinesFinalAndVolatile() {
        var collector = LiveTranscriptCollector()
        collector.apply(text: "Erster Satz.", isFinal: true)
        collector.apply(text: "Zweiter unfer", isFinal: false)
        XCTAssertEqual(collector.displayText, "Erster Satz. Zweiter unfer")
    }

    func testMultiSegmentDictationAccumulatesCompletely() {
        var collector = LiveTranscriptCollector()
        let segments = [
            "Dies ist der erste Abschnitt.",
            "Hier kommt der zweite Teil.",
            "Und schließlich der dritte.",
        ]
        for segment in segments {
            collector.apply(text: segment, isFinal: false)
            collector.apply(text: segment, isFinal: true)
        }
        XCTAssertEqual(
            collector.finalText,
            "Dies ist der erste Abschnitt. Hier kommt der zweite Teil. Und schließlich der dritte."
        )
    }

    func testAbsorbVolatileMergesPendingVolatileIntoFinal() {
        var collector = LiveTranscriptCollector()
        collector.apply(text: "Fertig.", isFinal: true)
        collector.apply(text: "Noch offen", isFinal: false)
        let result = collector.absorbVolatile()
        _ = result
        XCTAssertEqual(collector.finalText, "Fertig. Noch offen")
        XCTAssertEqual(collector.volatileText, "")
    }

    func testAbsorbVolatileNoOpWhenEmpty() {
        var collector = LiveTranscriptCollector()
        collector.apply(text: "Nur final.", isFinal: true)
        collector.absorbVolatile()
        XCTAssertEqual(collector.finalText, "Nur final.")
    }

    func testFinalizedTextTrimsWhitespace() {
        var collector = LiveTranscriptCollector()
        collector.apply(text: "  Text mit Leerzeichen.  ", isFinal: true)
        XCTAssertEqual(collector.finalizedText, "Text mit Leerzeichen.")
    }
}
