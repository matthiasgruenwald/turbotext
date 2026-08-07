import XCTest
@testable import Turbotext

/// Covers `TranscriptionBackendResolver.resolve` (#123, #193): the single decider for both
/// the resolved backend and the warning sound that belongs to it. Before #193 the sound was
/// decided separately, by `OfflineWarningSoundDecision`/`TranscriptionFallbackResolver`
/// (removed) — those tests live here now, expressed against the merged decision.
final class TranscriptionBackendResolverTests: XCTestCase {

    // MARK: Rule 1 — alwaysLocalTranscription wins outright, never plays a sound

    func testAlwaysLocalWithAppleSpeechAvailablePicksAppleSpeechEvenWhenOnline() {
        let decision = TranscriptionBackendResolver.resolve(
            alwaysLocalTranscription: true,
            appleSpeechAvailable: true,
            isOnline: true,
            autoFallbackToLocalOnOffline: false,
            whisperKitModelInstalled: false
        )
        XCTAssertEqual(decision.backend, .appleSpeech)
        XCTAssertNil(decision.warningSound)
    }

    func testAlwaysLocalWithAppleSpeechAvailablePicksAppleSpeechEvenWhenOffline() {
        let decision = TranscriptionBackendResolver.resolve(
            alwaysLocalTranscription: true,
            appleSpeechAvailable: true,
            isOnline: false,
            autoFallbackToLocalOnOffline: false,
            whisperKitModelInstalled: false
        )
        XCTAssertEqual(decision.backend, .appleSpeech)
        XCTAssertNil(decision.warningSound)
    }

    func testAlwaysLocalWithWhisperKitSelectedPicksWhisperKit() {
        let decision = TranscriptionBackendResolver.resolve(
            alwaysLocalTranscription: true,
            selectedLocalBackend: .whisperKit,
            appleSpeechAvailable: true,
            isOnline: true,
            autoFallbackToLocalOnOffline: false,
            whisperKitModelInstalled: true
        )
        XCTAssertEqual(decision.backend, .whisperKit)
        XCTAssertNil(decision.warningSound)
    }

    func testAlwaysLocalWithUnavailableAppleSpeechDoesNotSilentlyUseRemote() {
        let decision = TranscriptionBackendResolver.resolve(
            alwaysLocalTranscription: true,
            selectedLocalBackend: .appleSpeech,
            appleSpeechAvailable: false,
            isOnline: true,
            autoFallbackToLocalOnOffline: false,
            whisperKitModelInstalled: true
        )
        XCTAssertEqual(decision.backend, .unavailable)
        XCTAssertNil(decision.warningSound)
    }

    func testAlwaysLocalWithUnavailableAppleSpeechDoesNotFallThroughToRemoteWhenOnline() {
        let decision = TranscriptionBackendResolver.resolve(
            alwaysLocalTranscription: true,
            selectedLocalBackend: .appleSpeech,
            appleSpeechAvailable: false,
            isOnline: true,
            autoFallbackToLocalOnOffline: false,
            whisperKitModelInstalled: false
        )
        XCTAssertEqual(decision.backend, .unavailable)
        XCTAssertNil(decision.warningSound)
    }

    // MARK: Rule 2 — online wins once Apple Speech isn't forced, never plays a sound

    func testOnlinePicksRemoteWhenAlwaysLocalIsOff() {
        let decision = TranscriptionBackendResolver.resolve(
            alwaysLocalTranscription: false,
            appleSpeechAvailable: true,
            isOnline: true,
            autoFallbackToLocalOnOffline: true,
            whisperKitModelInstalled: true
        )
        XCTAssertEqual(decision.backend, .remote)
        XCTAssertNil(decision.warningSound)
    }

    // MARK: Rule 3 — offline auto-fallback to Apple Speech plays the "local fallback" sound

    func testOfflineWithAutoFallbackAndAppleSpeechAvailablePicksAppleSpeech() {
        let decision = TranscriptionBackendResolver.resolve(
            alwaysLocalTranscription: false,
            appleSpeechAvailable: true,
            isOnline: false,
            autoFallbackToLocalOnOffline: true,
            whisperKitModelInstalled: false
        )
        XCTAssertEqual(decision.backend, .appleSpeech)
        XCTAssertEqual(decision.warningSound, .localFallbackActive)
    }

    func testOfflineWithAutoFallbackDisabledDoesNotPickAppleSpeechAndWarns() {
        let decision = TranscriptionBackendResolver.resolve(
            alwaysLocalTranscription: false,
            appleSpeechAvailable: true,
            isOnline: false,
            autoFallbackToLocalOnOffline: false,
            whisperKitModelInstalled: false
        )
        XCTAssertEqual(decision.backend, .remote)
        XCTAssertEqual(decision.warningSound, .networkUnavailable)
    }

    // MARK: Rule 4 — legacy WhisperKit, derived from the settings' selected local backend
    // (#193) rather than a caller-supplied override, only when a model is installed

    func testOfflineWhisperKitSelectedWithModelInstalledPicksWhisperKitAndPlaysFallbackSound() {
        let decision = TranscriptionBackendResolver.resolve(
            alwaysLocalTranscription: false,
            selectedLocalBackend: .whisperKit,
            appleSpeechAvailable: false,
            isOnline: false,
            autoFallbackToLocalOnOffline: false,
            whisperKitModelInstalled: true
        )
        XCTAssertEqual(decision.backend, .whisperKit)
        XCTAssertEqual(decision.warningSound, .localFallbackActive)
    }

    func testOfflineWhisperKitSelectedWithoutModelInstalledFallsBackToRemoteAndWarns() {
        let decision = TranscriptionBackendResolver.resolve(
            alwaysLocalTranscription: false,
            selectedLocalBackend: .whisperKit,
            appleSpeechAvailable: false,
            isOnline: false,
            autoFallbackToLocalOnOffline: false,
            whisperKitModelInstalled: false
        )
        XCTAssertEqual(decision.backend, .remote)
        XCTAssertEqual(decision.warningSound, .networkUnavailable)
    }

    /// Apple Speech availability still beats the legacy WhisperKit selection when offline —
    /// #123 requires the auto-fallback to prefer Apple Speech over WhisperKit wherever possible.
    func testOfflineAutoFallbackPrefersAppleSpeechOverWhisperKitSelection() {
        let decision = TranscriptionBackendResolver.resolve(
            alwaysLocalTranscription: false,
            selectedLocalBackend: .whisperKit,
            appleSpeechAvailable: true,
            isOnline: false,
            autoFallbackToLocalOnOffline: true,
            whisperKitModelInstalled: true
        )
        XCTAssertEqual(decision.backend, .appleSpeech)
        XCTAssertEqual(decision.warningSound, .localFallbackActive)
    }

    // MARK: Nothing usable → remote with a warning sound (surfaces as the existing "no API key" error path)

    func testOfflineWithNothingAvailableFallsBackToRemoteAndWarns() {
        let decision = TranscriptionBackendResolver.resolve(
            alwaysLocalTranscription: false,
            appleSpeechAvailable: false,
            isOnline: false,
            autoFallbackToLocalOnOffline: false,
            whisperKitModelInstalled: false
        )
        XCTAssertEqual(decision.backend, .remote)
        XCTAssertEqual(decision.warningSound, .networkUnavailable)
    }
}
