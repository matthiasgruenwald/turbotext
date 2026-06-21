import XCTest
import AppKit
@testable import Turbotext

final class DockModeServiceTests: XCTestCase {

    func testPolicyForEnabledIsRegular() {
        XCTAssertEqual(DockModeService.policy(forDockModeEnabled: true), .regular)
    }

    func testPolicyForDisabledIsAccessory() {
        XCTAssertEqual(DockModeService.policy(forDockModeEnabled: false), .accessory)
    }
}
