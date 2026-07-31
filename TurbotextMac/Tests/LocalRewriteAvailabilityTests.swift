import XCTest
@testable import Turbotext

final class LocalRewriteAvailabilityTests: XCTestCase {

    func testAvailableShowsLocalFirstExplanation() {
        let status = LocalRewriteAvailability.available

        XCTAssertTrue(status.isAvailable)
        XCTAssertEqual(status.statusLabel, "Lokale Textverbesserung verfügbar")
        XCTAssertTrue(status.detailText.contains("lokal auf diesem Mac"))
    }

    func testAvailableNamesTheThreeWorkflows() {
        let detail = LocalRewriteAvailability.available.detailText

        XCTAssertTrue(detail.contains("Textverbesserung"))
        XCTAssertTrue(detail.contains("Dampf ablassen"))
        XCTAssertTrue(detail.contains("Emoji-Text"))
    }

    func testAvailableExplainsOnlineFallbackRequiresConsent() {
        let detail = LocalRewriteAvailability.available.detailText

        XCTAssertTrue(detail.contains("Erlaubnis"))
    }

    func testRequiresNewerMacOSShowsNotAvailableWithReason() {
        let status = LocalRewriteAvailability.requiresNewerMacOS

        XCTAssertFalse(status.isAvailable)
        XCTAssertEqual(status.statusLabel, "Lokale Textverbesserung nicht verfügbar")
        XCTAssertTrue(status.detailText.contains("macOS 26"))
    }

    func testAppleIntelligenceNotEnabledShowsNotAvailableWithReason() {
        let status = LocalRewriteAvailability.appleIntelligenceNotEnabled

        XCTAssertFalse(status.isAvailable)
        XCTAssertEqual(status.statusLabel, "Lokale Textverbesserung nicht verfügbar")
        XCTAssertTrue(status.detailText.contains("Apple Intelligence"))
    }

    func testAvailableIconIsCheckmark() {
        XCTAssertEqual(LocalRewriteAvailability.available.statusIconName, "checkmark.circle.fill")
    }

    func testUnavailableIconsAreXmark() {
        XCTAssertEqual(LocalRewriteAvailability.requiresNewerMacOS.statusIconName, "xmark.circle.fill")
        XCTAssertEqual(LocalRewriteAvailability.appleIntelligenceNotEnabled.statusIconName, "xmark.circle.fill")
    }
}
