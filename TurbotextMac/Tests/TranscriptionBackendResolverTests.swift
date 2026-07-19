import XCTest
@testable import Turbotext

final class TranscriptionBackendResolverTests: XCTestCase {

    // MARK: Rule 1 — alwaysLocalTranscription + Apple Speech available wins outright

    func testAlwaysLocalWithAppleSpeechAvailablePicksAppleSpeechEvenWhenOnline() {
        let result = TranscriptionBackendResolver.resolve(
            alwaysLocalTranscription: true,
            appleSpeechAvailable: true,
            isOnline: true,
            autoFallbackToLocalOnOffline: false,
            legacyWhisperKitRequested: false,
            whisperKitModelInstalled: false
        )
        XCTAssertEqual(result, .appleSpeech)
    }

    func testAlwaysLocalWithAppleSpeechAvailablePicksAppleSpeechEvenWhenOffline() {
        let result = TranscriptionBackendResolver.resolve(
            alwaysLocalTranscription: true,
            appleSpeechAvailable: true,
            isOnline: false,
            autoFallbackToLocalOnOffline: false,
            legacyWhisperKitRequested: false,
            whisperKitModelInstalled: false
        )
        XCTAssertEqual(result, .appleSpeech)
    }

    func testAlwaysLocalWithWhisperKitSelectedPicksWhisperKit() {
        let result = TranscriptionBackendResolver.resolve(
            alwaysLocalTranscription: true,
            selectedLocalBackend: .whisperKit,
            appleSpeechAvailable: true,
            isOnline: true,
            autoFallbackToLocalOnOffline: false,
            legacyWhisperKitRequested: false,
            whisperKitModelInstalled: true
        )
        XCTAssertEqual(result, .whisperKit)
    }

    func testAlwaysLocalWithUnavailableAppleSpeechDoesNotSilentlyUseRemote() {
        let result = TranscriptionBackendResolver.resolve(
            alwaysLocalTranscription: true,
            selectedLocalBackend: .appleSpeech,
            appleSpeechAvailable: false,
            isOnline: true,
            autoFallbackToLocalOnOffline: false,
            legacyWhisperKitRequested: false,
            whisperKitModelInstalled: true
        )
        XCTAssertEqual(result, .unavailable)
    }

    // MARK: Rule 2 — online wins once Apple Speech isn't forced/available

    func testOnlinePicksRemoteWhenAlwaysLocalIsOff() {
        let result = TranscriptionBackendResolver.resolve(
            alwaysLocalTranscription: false,
            appleSpeechAvailable: true,
            isOnline: true,
            autoFallbackToLocalOnOffline: true,
            legacyWhisperKitRequested: false,
            whisperKitModelInstalled: true
        )
        XCTAssertEqual(result, .remote)
    }

    func testAlwaysLocalWithUnavailableAppleSpeechDoesNotFallThroughToRemoteWhenOnline() {
        let result = TranscriptionBackendResolver.resolve(
            alwaysLocalTranscription: true,
            selectedLocalBackend: .appleSpeech,
            appleSpeechAvailable: false,
            isOnline: true,
            autoFallbackToLocalOnOffline: false,
            legacyWhisperKitRequested: false,
            whisperKitModelInstalled: false
        )
        XCTAssertEqual(result, .unavailable)
    }

    // MARK: Rule 3 — offline auto-fallback to Apple Speech

    func testOfflineWithAutoFallbackAndAppleSpeechAvailablePicksAppleSpeech() {
        let result = TranscriptionBackendResolver.resolve(
            alwaysLocalTranscription: false,
            appleSpeechAvailable: true,
            isOnline: false,
            autoFallbackToLocalOnOffline: true,
            legacyWhisperKitRequested: false,
            whisperKitModelInstalled: false
        )
        XCTAssertEqual(result, .appleSpeech)
    }

    func testOfflineWithAutoFallbackDisabledDoesNotPickAppleSpeech() {
        let result = TranscriptionBackendResolver.resolve(
            alwaysLocalTranscription: false,
            appleSpeechAvailable: true,
            isOnline: false,
            autoFallbackToLocalOnOffline: false,
            legacyWhisperKitRequested: false,
            whisperKitModelInstalled: false
        )
        XCTAssertEqual(result, .remote)
    }

    // MARK: Rule 4 — explicit legacy WhisperKit request, only when a model is installed

    func testOfflineLegacyWhisperKitRequestedWithModelInstalledPicksWhisperKit() {
        let result = TranscriptionBackendResolver.resolve(
            alwaysLocalTranscription: false,
            appleSpeechAvailable: false,
            isOnline: false,
            autoFallbackToLocalOnOffline: false,
            legacyWhisperKitRequested: true,
            whisperKitModelInstalled: true
        )
        XCTAssertEqual(result, .whisperKit)
    }

    func testOfflineLegacyWhisperKitRequestedWithoutModelInstalledFallsBackToRemote() {
        let result = TranscriptionBackendResolver.resolve(
            alwaysLocalTranscription: false,
            appleSpeechAvailable: false,
            isOnline: false,
            autoFallbackToLocalOnOffline: false,
            legacyWhisperKitRequested: true,
            whisperKitModelInstalled: false
        )
        XCTAssertEqual(result, .remote)
    }

    /// Apple Speech availability still beats an explicit legacy request when offline —
    /// #123 requires the auto-fallback to prefer Apple Speech over WhisperKit wherever possible.
    func testOfflineAutoFallbackPrefersAppleSpeechOverExplicitWhisperKitRequest() {
        let result = TranscriptionBackendResolver.resolve(
            alwaysLocalTranscription: false,
            appleSpeechAvailable: true,
            isOnline: false,
            autoFallbackToLocalOnOffline: true,
            legacyWhisperKitRequested: true,
            whisperKitModelInstalled: true
        )
        XCTAssertEqual(result, .appleSpeech)
    }

    // MARK: Nothing usable → remote (surfaces as the existing "no API key" error path)

    func testOfflineWithNothingAvailableFallsBackToRemote() {
        let result = TranscriptionBackendResolver.resolve(
            alwaysLocalTranscription: false,
            appleSpeechAvailable: false,
            isOnline: false,
            autoFallbackToLocalOnOffline: false,
            legacyWhisperKitRequested: false,
            whisperKitModelInstalled: false
        )
        XCTAssertEqual(result, .remote)
    }
}
