import XCTest
@testable import Turbotext

final class OnlineModeToggleTests: XCTestCase {

    func testRequestingOnlineAlwaysDisablesLocalMode() {
        let result = OnlineModeToggle.nextAlwaysLocalTranscription(requestedOnline: true, localModelInstalled: false)
        XCTAssertEqual(result, false)
    }

    func testRequestingOfflineEnablesLocalModeWhenSelectedWhisperKitModelIsInstalled() {
        let result = OnlineModeToggle.nextAlwaysLocalTranscription(
            requestedOnline: false,
            selectedLocalBackend: .whisperKit,
            localModelInstalled: true,
            appleSpeechAvailable: false
        )
        XCTAssertEqual(result, true)
    }

    func testRequestingOfflineIsBlockedWhenSelectedAppleSpeechAssetsAreUnavailable() {
        let result = OnlineModeToggle.nextAlwaysLocalTranscription(
            requestedOnline: false,
            selectedLocalBackend: .appleSpeech,
            localModelInstalled: true,
            appleSpeechAvailable: false
        )
        XCTAssertNil(result)
    }

    func testToggleEnabledWhileOnlineAndModelMissing() {
        XCTAssertFalse(OnlineModeToggle.isToggleEnabled(alwaysLocalTranscription: false, localModelInstalled: false))
    }

    func testToggleEnabledWhileOnlineAndSelectedWhisperKitModelInstalled() {
        XCTAssertTrue(OnlineModeToggle.isToggleEnabled(
            alwaysLocalTranscription: false,
            selectedLocalBackend: .whisperKit,
            localModelInstalled: true
        ))
    }

    func testToggleIsDisabledWhenSelectedWhisperKitModelIsMissingDespiteAvailableAppleSpeech() {
        XCTAssertFalse(OnlineModeToggle.isToggleEnabled(
            alwaysLocalTranscription: false,
            selectedLocalBackend: .whisperKit,
            localModelInstalled: false,
            appleSpeechAvailable: true
        ))
    }

    func testToggleAlwaysEnabledWhileOffline() {
        XCTAssertTrue(OnlineModeToggle.isToggleEnabled(alwaysLocalTranscription: true, localModelInstalled: false))
        XCTAssertTrue(OnlineModeToggle.isToggleEnabled(
            alwaysLocalTranscription: true,
            selectedLocalBackend: .whisperKit,
            localModelInstalled: true
        ))
    }

    func testDisabledReasonExplainsMissingAppleAssetsWhileOnline() {
        let reason = OnlineModeToggle.disabledReason(alwaysLocalTranscription: false, localModelInstalled: false)
        XCTAssertEqual(reason, "Apple-Sprachassets müssen erst installiert werden, um offline zu wechseln.")
    }

    func testDisabledReasonIsNilWhenToggleEnabled() {
        XCTAssertNil(OnlineModeToggle.disabledReason(
            alwaysLocalTranscription: false,
            selectedLocalBackend: .whisperKit,
            localModelInstalled: true
        ))
        XCTAssertNil(OnlineModeToggle.disabledReason(alwaysLocalTranscription: true, localModelInstalled: false))
    }
}
