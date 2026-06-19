import XCTest
@testable import Turbotext

final class PopoverSizingTests: XCTestCase {

    func testGrowsWithContentBelowScreenLimit() {
        let height = PopoverSizing.clampedHeight(
            contentHeight: 400,
            chrome: 100,
            screenHeight: 900,
            minHeight: 420,
            screenMarginFraction: 0.9
        )
        XCTAssertEqual(height, 500, accuracy: 0.001)
    }

    func testNeverShrinksBelowMinHeight() {
        let height = PopoverSizing.clampedHeight(
            contentHeight: 50,
            chrome: 100,
            screenHeight: 900,
            minHeight: 420,
            screenMarginFraction: 0.9
        )
        XCTAssertEqual(height, 420, accuracy: 0.001)
    }

    func testCapsAtScreenMarginWhenContentExceedsIt() {
        let height = PopoverSizing.clampedHeight(
            contentHeight: 2000,
            chrome: 100,
            screenHeight: 900,
            minHeight: 420,
            screenMarginFraction: 0.9
        )
        XCTAssertEqual(height, 810, accuracy: 0.001)
    }
}

final class AutoGrowingTextHeightTests: XCTestCase {

    func testGrowsWithMeasuredContentBetweenBounds() {
        let height = AutoGrowingTextHeight.clamped(measured: 120, minHeight: 64, maxHeight: 220)
        XCTAssertEqual(height, 120, accuracy: 0.001)
    }

    func testNeverShrinksBelowMinHeight() {
        let height = AutoGrowingTextHeight.clamped(measured: 10, minHeight: 64, maxHeight: 220)
        XCTAssertEqual(height, 64, accuracy: 0.001)
    }

    func testCapsAtMaxHeightAndLetsTextEditorScrollBeyondThat() {
        let height = AutoGrowingTextHeight.clamped(measured: 500, minHeight: 64, maxHeight: 220)
        XCTAssertEqual(height, 220, accuracy: 0.001)
    }
}
