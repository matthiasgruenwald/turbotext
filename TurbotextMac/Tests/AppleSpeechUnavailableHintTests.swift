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

    func testExplainsEachUnavailableAppleSpeechStatus() {
        XCTAssertEqual(
            AppleSpeechUnavailableHint.text(for: .unsupportedOS),
            "Apple-Gerätetranskription erfordert macOS 26 oder neuer."
        )
        XCTAssertEqual(
            AppleSpeechUnavailableHint.text(for: .assetsNotInstalled),
            "Die deutschen Sprachassets für Apple-Gerätetranskription sind nicht installiert."
        )
        XCTAssertEqual(
            AppleSpeechUnavailableHint.text(for: .assetsDownloading),
            "Die deutschen Sprachassets für Apple-Gerätetranskription werden noch installiert."
        )
    }
}
