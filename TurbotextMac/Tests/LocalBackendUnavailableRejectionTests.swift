import XCTest
@testable import Turbotext

/// Covers `LocalBackendUnavailableRejection` (#192, fixes F2 from #188 fully): a pure
/// function, so the "install Sprachassets automatically when the rejection reason is an
/// installable readiness gap" acceptance criterion is testable without constructing
/// `AppState`'s real `AppleSpeechAvailability`.
final class LocalBackendUnavailableRejectionTests: XCTestCase {

    func testInstallableAppleSpeechReadinessTriggersInstallAndReportsCanRetry() {
        let (rejection, shouldInstall) = LocalBackendUnavailableRejection.resolve(
            selectedBackend: .appleSpeech,
            appleSpeechReadiness: .notReady(reason: .assetsNotInstalled, canInstall: true)
        )

        XCTAssertTrue(shouldInstall, "an installable Sprachasset gap must trigger installation")
        XCTAssertTrue(rejection.canRetryImmediately)
        XCTAssertEqual(rejection.reason, "appleSpeech.assetsNotInstalled")
    }

    func testAssetsAlreadyDownloadingTriggersInstallAgain() {
        let (_, shouldInstall) = LocalBackendUnavailableRejection.resolve(
            selectedBackend: .appleSpeech,
            appleSpeechReadiness: .notReady(reason: .assetsDownloading, canInstall: true)
        )

        XCTAssertTrue(shouldInstall)
    }

    func testUnsupportedOSDoesNotTriggerInstall() {
        let (rejection, shouldInstall) = LocalBackendUnavailableRejection.resolve(
            selectedBackend: .appleSpeech,
            appleSpeechReadiness: .notReady(reason: .unsupportedOS, canInstall: false)
        )

        XCTAssertFalse(shouldInstall, "nothing installable when the OS itself is unsupported")
        XCTAssertFalse(rejection.canRetryImmediately)
    }

    func testGermanAssetsUnsupportedDoesNotTriggerInstall() {
        let (_, shouldInstall) = LocalBackendUnavailableRejection.resolve(
            selectedBackend: .appleSpeech,
            appleSpeechReadiness: .notReady(reason: .germanAssetsUnsupported, canInstall: false)
        )

        XCTAssertFalse(shouldInstall)
    }

    func testLegacyWhisperKitNeverTriggersInstall() {
        let (rejection, shouldInstall) = LocalBackendUnavailableRejection.resolve(
            selectedBackend: .whisperKit,
            appleSpeechReadiness: .ready
        )

        XCTAssertFalse(shouldInstall, "WhisperKit models are a manual download, not an auto-installable Sprachasset")
        XCTAssertEqual(rejection.reason, "localModelNotInstalled")
        XCTAssertEqual(rejection.message, LocalBackendUnavailableRejection.whisperKitModelNotInstalledMessage)
    }

    /// Defensive-only path: `.unavailable` for `.appleSpeech` implies `.notReady` in
    /// practice (`TranscriptionBackendResolver` only reports `.unavailable` when
    /// `appleSpeechAvailable` is false), but `resolve` still needs a sane answer if
    /// called with `.ready` anyway.
    func testAppleSpeechAlreadyReadyDoesNotTriggerInstall() {
        let (_, shouldInstall) = LocalBackendUnavailableRejection.resolve(
            selectedBackend: .appleSpeech,
            appleSpeechReadiness: .ready
        )

        XCTAssertFalse(shouldInstall)
    }
}
