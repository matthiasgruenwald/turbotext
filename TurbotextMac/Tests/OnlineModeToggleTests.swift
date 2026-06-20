import XCTest
@testable import Turbotext

final class OnlineModeToggleTests: XCTestCase {

    func testRequestingOnlineAlwaysDisablesLocalMode() {
        let result = OnlineModeToggle.nextSecureLocalModeEnabled(requestedOnline: true, localModelInstalled: false)
        XCTAssertEqual(result, false)
    }

    func testRequestingOfflineEnablesLocalModeWhenModelInstalled() {
        let result = OnlineModeToggle.nextSecureLocalModeEnabled(requestedOnline: false, localModelInstalled: true)
        XCTAssertEqual(result, true)
    }

    func testRequestingOfflineIsBlockedWhenModelNotInstalled() {
        let result = OnlineModeToggle.nextSecureLocalModeEnabled(requestedOnline: false, localModelInstalled: false)
        XCTAssertNil(result)
    }

    func testToggleEnabledWhileOnlineAndModelMissing() {
        XCTAssertFalse(OnlineModeToggle.isToggleEnabled(secureLocalModeEnabled: false, localModelInstalled: false))
    }

    func testToggleEnabledWhileOnlineAndModelInstalled() {
        XCTAssertTrue(OnlineModeToggle.isToggleEnabled(secureLocalModeEnabled: false, localModelInstalled: true))
    }

    func testToggleAlwaysEnabledWhileOffline() {
        XCTAssertTrue(OnlineModeToggle.isToggleEnabled(secureLocalModeEnabled: true, localModelInstalled: false))
        XCTAssertTrue(OnlineModeToggle.isToggleEnabled(secureLocalModeEnabled: true, localModelInstalled: true))
    }
}
