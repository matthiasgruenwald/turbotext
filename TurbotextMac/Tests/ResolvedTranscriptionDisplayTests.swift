import XCTest
@testable import Turbotext

final class ResolvedTranscriptionDisplayTests: XCTestCase {

    func testAppleDeviceTranscriptionIsNamedInPanelAndWorkflow() {
        let status = makeStatus(alwaysLocal: true, selectedBackend: .appleSpeech, appleSpeechAvailable: true)

        XCTAssertEqual(status.panelSubtitle, "Verarbeitung auf diesem Gerät mit Apple-Gerätetranskription.")
        XCTAssertEqual(status.transcriptionWorkflowSubtitle, "Lokal: Apple-Gerätetranskription.")
    }

    func testWhisperKitNamesTheSelectedModelInPanelAndWorkflow() {
        let status = makeStatus(
            alwaysLocal: true,
            selectedBackend: .whisperKit,
            whisperKitModelInstalled: true
        )

        XCTAssertEqual(status.panelSubtitle, "Verarbeitung auf diesem Gerät mit Whisper Small.")
        XCTAssertEqual(status.transcriptionWorkflowSubtitle, "Lokal: Whisper Small.")
    }

    func testOfflineFallbackNamesAppleDeviceTranscriptionInPanelAndWorkflow() {
        let status = makeStatus(
            alwaysLocal: false,
            appleSpeechAvailable: true,
            isOnline: false,
            autoFallbackToLocalOnOffline: true
        )

        XCTAssertEqual(status.panelSubtitle, "Offline-Fallback: Apple-Gerätetranskription auf diesem Gerät.")
        XCTAssertEqual(status.transcriptionWorkflowSubtitle, "Offline-Fallback: Apple-Gerätetranskription.")
    }

    func testUnavailableSelectedWhisperKitModelIsNamedAsUnavailable() {
        let status = makeStatus(
            alwaysLocal: true,
            selectedBackend: .whisperKit,
            whisperKitModelInstalled: false
        )

        XCTAssertEqual(status.panelSubtitle, "Whisper Small ist nicht nutzbar, weil es nicht installiert ist.")
        XCTAssertEqual(status.transcriptionWorkflowSubtitle, "Whisper Small ist nicht nutzbar, weil es nicht installiert ist.")
    }

    private func makeStatus(
        alwaysLocal: Bool,
        selectedBackend: LocalTranscriptionBackend = .appleSpeech,
        appleSpeechAvailable: Bool = false,
        whisperKitModelInstalled: Bool = false,
        isOnline: Bool = true,
        autoFallbackToLocalOnOffline: Bool = false
    ) -> TranscriptionModeStatus {
        TranscriptionModeStatus(
            alwaysLocalTranscription: alwaysLocal,
            selectedLocalBackend: selectedBackend,
            appleSpeechAvailable: appleSpeechAvailable,
            selectedLocalModelInstalled: whisperKitModelInstalled,
            selectedLocalModelDisplayName: "Whisper Small",
            isDownloadingLocalModel: false,
            localModelDownloadStatusText: nil,
            hasGroqKey: false,
            groqFallbackActive: false,
            groqQuotaUsedToday: "0 min",
            isOnline: isOnline,
            autoFallbackToLocalOnOffline: autoFallbackToLocalOnOffline
        )
    }
}
