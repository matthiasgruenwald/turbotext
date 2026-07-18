import XCTest
@testable import Turbotext

final class AppleSpeechUnavailableHintTests: XCTestCase {

    func testReturnsNilWhenAvailable() {
        XCTAssertNil(AppleSpeechUnavailableHint.text(isAvailable: true))
    }

    func testReturnsExplanationWhenUnavailable() {
        let text = AppleSpeechUnavailableHint.text(isAvailable: false)
        XCTAssertNotNil(text)
        XCTAssertFalse(text?.isEmpty ?? true)
    }
}
