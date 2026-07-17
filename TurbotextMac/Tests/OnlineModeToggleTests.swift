import XCTest
@testable import Turbotext

final class OnlineModeToggleTests: XCTestCase {

    func testRequestingOnlineAlwaysDisablesLocalMode() {
        let result = OnlineModeToggle.nextAlwaysLocalTranscription(requestedOnline: true, localModelInstalled: false)
        XCTAssertEqual(result, false)
    }

    func testRequestingOfflineEnablesLocalModeWhenModelInstalled() {
        let result = OnlineModeToggle.nextAlwaysLocalTranscription(requestedOnline: false, localModelInstalled: true)
        XCTAssertEqual(result, true)
    }

    func testRequestingOfflineIsBlockedWhenModelNotInstalled() {
        let result = OnlineModeToggle.nextAlwaysLocalTranscription(requestedOnline: false, localModelInstalled: false)
        XCTAssertNil(result)
    }

    func testToggleEnabledWhileOnlineAndModelMissing() {
        XCTAssertFalse(OnlineModeToggle.isToggleEnabled(alwaysLocalTranscription: false, localModelInstalled: false))
    }

    func testToggleEnabledWhileOnlineAndModelInstalled() {
        XCTAssertTrue(OnlineModeToggle.isToggleEnabled(alwaysLocalTranscription: false, localModelInstalled: true))
    }

    func testToggleAlwaysEnabledWhileOffline() {
        XCTAssertTrue(OnlineModeToggle.isToggleEnabled(alwaysLocalTranscription: true, localModelInstalled: false))
        XCTAssertTrue(OnlineModeToggle.isToggleEnabled(alwaysLocalTranscription: true, localModelInstalled: true))
    }

    func testDisabledReasonExplainsMissingModelWhileOnline() {
        let reason = OnlineModeToggle.disabledReason(alwaysLocalTranscription: false, localModelInstalled: false)
        XCTAssertEqual(reason, "Lokales Modell muss erst installiert werden, um offline zu wechseln.")
    }

    func testDisabledReasonIsNilWhenToggleEnabled() {
        XCTAssertNil(OnlineModeToggle.disabledReason(alwaysLocalTranscription: false, localModelInstalled: true))
        XCTAssertNil(OnlineModeToggle.disabledReason(alwaysLocalTranscription: true, localModelInstalled: false))
    }
}
