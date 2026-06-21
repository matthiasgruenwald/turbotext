import XCTest
@testable import Turbotext

@MainActor
final class MenuBarClickDispatchTests: XCTestCase {

    func testBringsMainWindowToFrontWhenWindowIsOpen() {
        let action = MenuBarClickDispatch.decide(mainWindowIsOpen: true, popoverIsShown: false)
        XCTAssertEqual(action, .bringMainWindowToFront)
    }

    func testBringsMainWindowToFrontWhenWindowIsOpenEvenIfPopoverSomehowShown() {
        let action = MenuBarClickDispatch.decide(mainWindowIsOpen: true, popoverIsShown: true)
        XCTAssertEqual(action, .bringMainWindowToFront)
    }

    func testOpensPopoverWhenNoMainWindowAndPopoverClosed() {
        let action = MenuBarClickDispatch.decide(mainWindowIsOpen: false, popoverIsShown: false)
        XCTAssertEqual(action, .openPopover)
    }

    func testClosesPopoverWhenNoMainWindowAndPopoverAlreadyShown() {
        let action = MenuBarClickDispatch.decide(mainWindowIsOpen: false, popoverIsShown: true)
        XCTAssertEqual(action, .closePopover)
    }
}
