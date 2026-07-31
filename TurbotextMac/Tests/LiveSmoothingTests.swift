import XCTest
@testable import Turbotext

final class LiveSmoothingTests: XCTestCase {

    func testPassthroughReturnsSegmentUnchanged() async {
        let smoothing = PassthroughSmoothing()

        let result = await smoothing.smooth(segment: "das ist ein rohes segment", context: nil)

        XCTAssertEqual(result, "das ist ein rohes segment")
    }

    func testPassthroughIgnoresContext() async {
        let smoothing = PassthroughSmoothing()

        let result = await smoothing.smooth(
            segment: "  segment mit leerzeichen  ",
            context: "voellig anderer vorheriger kontext"
        )

        XCTAssertEqual(result, "  segment mit leerzeichen  ")
    }

    func testPassthroughReturnsEmptySegmentUnchanged() async {
        let smoothing = PassthroughSmoothing()

        let result = await smoothing.smooth(segment: "", context: "kontext")

        XCTAssertEqual(result, "")
    }

    func testPassthroughIsUsableThroughProtocol() async {
        let smoothing: any LiveSmoothing = PassthroughSmoothing()

        let result = await smoothing.smooth(segment: "protokoll aufruf", context: nil)

        XCTAssertEqual(result, "protokoll aufruf")
    }

    func testContextTailReturnsShortSegmentTrimmed() {
        XCTAssertEqual(LiveSmoothingContext.tail(of: "  kurzes segment  "), "kurzes segment")
    }

    func testContextTailReturnsNilForWhitespaceOnlySegment() {
        XCTAssertNil(LiveSmoothingContext.tail(of: "   \n\t  "))
    }

    func testContextTailKeepsLastCharactersOfLongSegment() {
        let segment = String(repeating: "a", count: 120) + "ENDE"

        let tail = LiveSmoothingContext.tail(of: segment, maxLength: 100)

        XCTAssertEqual(tail?.count, 100)
        XCTAssertTrue(tail?.hasSuffix("ENDE") ?? false)
    }

    func testContextTailRespectsCustomMaxLength() {
        let tail = LiveSmoothingContext.tail(of: "abcdefghij", maxLength: 4)

        XCTAssertEqual(tail, "ghij")
    }
}
