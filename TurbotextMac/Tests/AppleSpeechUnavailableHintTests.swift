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
            "Sprachassets werden geladen – bitte gleich erneut versuchen."
        )
        XCTAssertEqual(
            AppleSpeechUnavailableHint.text(for: .assetsDownloading),
            "Sprachassets werden geladen – bitte gleich erneut versuchen."
        )
        XCTAssertEqual(
            AppleSpeechUnavailableHint.text(for: .germanAssetsUnsupported),
            "Deutsche Sprachassets für Apple-Gerätetranskription werden auf diesem Mac nicht unterstützt."
        )
    }

    func testRefusalTextMatchesTheUnavailableHint() {
        XCTAssertEqual(
            AppleSpeechUnavailableHint.refusalText(for: .assetsNotInstalled),
            "Sprachassets werden geladen – bitte gleich erneut versuchen."
        )
        XCTAssertEqual(
            AppleSpeechUnavailableHint.refusalText(for: .germanAssetsUnsupported),
            "Deutsche Sprachassets für Apple-Gerätetranskription werden auf diesem Mac nicht unterstützt."
        )
        XCTAssertEqual(
            AppleSpeechUnavailableHint.refusalText(for: .unsupportedOS),
            "Apple-Gerätetranskription erfordert macOS 26 oder neuer."
        )
    }

    func testAssetInstallationIsOnlyPossibleWhileAssetsCanStillBeLoaded() {
        XCTAssertTrue(AppleSpeechAvailabilityStatus.assetsNotInstalled.isAssetInstallationPossible)
        XCTAssertTrue(AppleSpeechAvailabilityStatus.assetsDownloading.isAssetInstallationPossible)
        XCTAssertFalse(AppleSpeechAvailabilityStatus.available.isAssetInstallationPossible)
        XCTAssertFalse(AppleSpeechAvailabilityStatus.unsupportedOS.isAssetInstallationPossible)
        XCTAssertFalse(AppleSpeechAvailabilityStatus.germanAssetsUnsupported.isAssetInstallationPossible)
    }
}
