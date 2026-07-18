import XCTest
@testable import Turbotext

final class AppleSpeechMigrationHintBannerTests: XCTestCase {

    func testReturnsNilWhenAlreadySeen() {
        XCTAssertNil(AppleSpeechMigrationHintBanner.content(
            isMacOS26OrLater: true,
            whisperKitModelInstalled: true,
            appleSpeechAvailable: true,
            hasSeenHint: true
        ))
    }

    func testReturnsNilWhenNotMacOS26() {
        XCTAssertNil(AppleSpeechMigrationHintBanner.content(
            isMacOS26OrLater: false,
            whisperKitModelInstalled: true,
            appleSpeechAvailable: true,
            hasSeenHint: false
        ))
    }

    func testReturnsNilWhenNoWhisperKitModelInstalled() {
        XCTAssertNil(AppleSpeechMigrationHintBanner.content(
            isMacOS26OrLater: true,
            whisperKitModelInstalled: false,
            appleSpeechAvailable: true,
            hasSeenHint: false
        ))
    }

    func testReturnsNilWhenAppleSpeechUnavailable() {
        XCTAssertNil(AppleSpeechMigrationHintBanner.content(
            isMacOS26OrLater: true,
            whisperKitModelInstalled: true,
            appleSpeechAvailable: false,
            hasSeenHint: false
        ))
    }

    func testReturnsContentWhenAllConditionsMet() {
        let content = AppleSpeechMigrationHintBanner.content(
            isMacOS26OrLater: true,
            whisperKitModelInstalled: true,
            appleSpeechAvailable: true,
            hasSeenHint: false
        )
        XCTAssertEqual(content?.title, "Apple-Gerätetranskription ist jetzt verfügbar.")
        XCTAssertEqual(content?.detail, "WhisperKit bleibt als Legacy-Option erhalten.")
    }
}
