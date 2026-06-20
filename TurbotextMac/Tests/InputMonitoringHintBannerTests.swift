import XCTest
@testable import Turbotext

final class InputMonitoringHintBannerTests: XCTestCase {

    func testShowsWhenNotGrantedAndNotDismissed() {
        XCTAssertTrue(InputMonitoringHintBanner.shouldShow(inputMonitoringGranted: false, dismissed: false))
    }

    func testHiddenWhenGranted() {
        XCTAssertFalse(InputMonitoringHintBanner.shouldShow(inputMonitoringGranted: true, dismissed: false))
    }

    func testHiddenWhenDismissed() {
        XCTAssertFalse(InputMonitoringHintBanner.shouldShow(inputMonitoringGranted: false, dismissed: true))
    }

    func testHiddenWhenGrantedAndDismissed() {
        XCTAssertFalse(InputMonitoringHintBanner.shouldShow(inputMonitoringGranted: true, dismissed: true))
    }
}
