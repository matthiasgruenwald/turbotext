import XCTest
@testable import Turbotext

final class TranscriptionQualityServiceTests: XCTestCase {
    func testRawInsertionMaxLengthIsFour() {
        XCTAssertEqual(TranscriptionQualityService.rawInsertionMaxLength, 4)
    }

    /// #173: the raw-insertion bound is one-sided — everything up to
    /// `rawInsertionMaxLength` qualifies; the `< minimumRewriteLength`
    /// rejection is a separate guard that runs before it.
    func testIsShortEnoughForRawInsertionBoundaries() {
        XCTAssertTrue(TranscriptionQualityService.isShortEnoughForRawInsertion("a"))
        XCTAssertTrue(TranscriptionQualityService.isShortEnoughForRawInsertion("ab"))
        XCTAssertTrue(TranscriptionQualityService.isShortEnoughForRawInsertion("abcd"))
        XCTAssertFalse(TranscriptionQualityService.isShortEnoughForRawInsertion("abcde"))
    }

    func testIsShortEnoughForRawInsertionCountsCleanedTranscript() {
        XCTAssertTrue(TranscriptionQualityService.isShortEnoughForRawInsertion("  ab \n"))
        XCTAssertFalse(TranscriptionQualityService.isShortEnoughForRawInsertion(" abcde \n"))
    }
}
