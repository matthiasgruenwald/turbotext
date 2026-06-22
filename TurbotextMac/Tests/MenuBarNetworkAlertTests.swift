import XCTest
@testable import Turbotext

final class MenuBarNetworkAlertTests: XCTestCase {

    func testShowsRedXWhenStatusIsRed() {
        XCTAssertTrue(MenuBarNetworkAlert.shouldShowRedX(for: .red))
    }

    func testHidesRedXWhenStatusIsYellow() {
        XCTAssertFalse(MenuBarNetworkAlert.shouldShowRedX(for: .yellow))
    }

    func testHidesRedXWhenStatusIsGreen() {
        XCTAssertFalse(MenuBarNetworkAlert.shouldShowRedX(for: .green))
    }
}
