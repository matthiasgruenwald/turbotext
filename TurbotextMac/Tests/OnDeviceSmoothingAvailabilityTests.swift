import FoundationModels
import XCTest
@testable import Turbotext

@available(macOS 26, *)
final class OnDeviceSmoothingAvailabilityTests: XCTestCase {

    func testAvailableModelWithGermanSupportIsAvailable() {
        let availability = OnDeviceSmoothingAvailability.resolve(
            systemAvailability: .available,
            supportsGerman: true
        )

        XCTAssertEqual(availability, .available)
        XCTAssertTrue(availability.isAvailable)
        XCTAssertNil(availability.reasonText)
    }

    func testAvailableModelWithoutGermanShowsMissingLanguageData() {
        let availability = OnDeviceSmoothingAvailability.resolve(
            systemAvailability: .available,
            supportsGerman: false
        )

        XCTAssertEqual(availability, .germanLanguageDataMissing)
        XCTAssertFalse(availability.isAvailable)
        XCTAssertNotNil(availability.reasonText)
    }

    func testDeviceNotEligibleMapsToReason() {
        let availability = OnDeviceSmoothingAvailability.resolve(
            systemAvailability: .unavailable(.deviceNotEligible),
            supportsGerman: false
        )

        XCTAssertEqual(availability, .deviceNotEligible)
        XCTAssertNotNil(availability.reasonText)
    }

    func testAppleIntelligenceNotEnabledMapsToReason() {
        let availability = OnDeviceSmoothingAvailability.resolve(
            systemAvailability: .unavailable(.appleIntelligenceNotEnabled),
            supportsGerman: false
        )

        XCTAssertEqual(availability, .appleIntelligenceNotEnabled)
        XCTAssertNotNil(availability.reasonText)
    }

    func testModelNotReadyMapsToReason() {
        let availability = OnDeviceSmoothingAvailability.resolve(
            systemAvailability: .unavailable(.modelNotReady),
            supportsGerman: false
        )

        XCTAssertEqual(availability, .modelNotReady)
        XCTAssertNotNil(availability.reasonText)
    }

    func testUnavailableReasonsDiffer() {
        XCTAssertNotEqual(OnDeviceSmoothingAvailability.deviceNotEligible, .appleIntelligenceNotEnabled)
        XCTAssertNotEqual(OnDeviceSmoothingAvailability.appleIntelligenceNotEnabled, .modelNotReady)
    }
}

final class OnDeviceSmoothingAvailabilityGateTests: XCTestCase {

    func testRequiresNewerMacOSBelowMacOS26() {
        guard #unavailable(macOS 26) else { return }
        XCTAssertEqual(OnDeviceSmoothingAvailability.current, .requiresNewerMacOS)
    }
}
