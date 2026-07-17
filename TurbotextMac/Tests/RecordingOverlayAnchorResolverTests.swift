import XCTest
@testable import Turbotext

final class RecordingOverlayAnchorResolverTests: XCTestCase {

    func testResolveUsesCaretRectWhenAvailable() {
        let caretRect = CGRect(x: 100, y: 200, width: 2, height: 16)

        let anchor = RecordingOverlayAnchorResolver.resolve(
            caretRectProvider: { caretRect },
            mouseLocationProvider: { CGPoint(x: 999, y: 999) }
        )

        XCTAssertEqual(anchor.source, .textCursor)
        XCTAssertEqual(anchor.point, CGPoint(x: caretRect.minX, y: caretRect.minY))
    }

    func testResolveFallsBackToMouseWhenCaretRectUnavailable() {
        let mousePoint = CGPoint(x: 42, y: 84)

        let anchor = RecordingOverlayAnchorResolver.resolve(
            caretRectProvider: { nil },
            mouseLocationProvider: { mousePoint }
        )

        XCTAssertEqual(anchor.source, .mousePointer)
        XCTAssertEqual(anchor.point, mousePoint)
    }
}
