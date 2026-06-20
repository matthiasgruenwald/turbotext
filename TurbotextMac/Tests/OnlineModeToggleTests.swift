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

    func testDisabledReasonExplainsMissingModelWhileOnline() {
        let reason = OnlineModeToggle.disabledReason(secureLocalModeEnabled: false, localModelInstalled: false)
        XCTAssertEqual(reason, "Lokales Modell muss erst installiert werden, um offline zu wechseln.")
    }

    func testDisabledReasonIsNilWhenToggleEnabled() {
        XCTAssertNil(OnlineModeToggle.disabledReason(secureLocalModeEnabled: false, localModelInstalled: true))
        XCTAssertNil(OnlineModeToggle.disabledReason(secureLocalModeEnabled: true, localModelInstalled: false))
    }
}
