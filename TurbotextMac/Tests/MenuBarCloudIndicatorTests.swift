import XCTest
@testable import Turbotext

final class MenuBarCloudIndicatorTests: XCTestCase {

    func testNoneWhileLocalModeEnabled() {
        XCTAssertEqual(localStatus.menuBarCloudIndicator, .none)
        XCTAssertEqual(localStatus.panelTitle, "Lokal · kein Server")
        XCTAssertEqual(localStatus.panelSubtitle, "Verarbeitung auf diesem Gerät mit Whisper Turbo.")
    }

    func testGroqReadyWhenKeyPresentAndNotFallenBack() {
        let status = remoteStatus(hasGroqKey: true, groqFallbackActive: false)
        XCTAssertEqual(status.menuBarCloudIndicator, .groqReady)
        XCTAssertEqual(status.panelTitle, "Online · Groq Whisper")
        XCTAssertEqual(status.panelSubtitle, "Über Server verarbeitet · heute 5 min Groq-Kontingent genutzt.")
    }

    func testOpenAIFallbackWhenNoGroqKey() {
        let status = remoteStatus(hasGroqKey: false, groqFallbackActive: false)
        XCTAssertEqual(status.menuBarCloudIndicator, .openAIFallback)
        XCTAssertEqual(status.panelTitle, "Online · OpenAI Whisper")
        XCTAssertEqual(status.panelSubtitle, "Über Server verarbeitet via OpenAI Whisper.")
    }

    func testOpenAIFallbackWhenGroqQuotaExhausted() {
        let status = remoteStatus(hasGroqKey: true, groqFallbackActive: true)
        XCTAssertEqual(status.menuBarCloudIndicator, .openAIFallback)
        XCTAssertEqual(status.panelTitle, "Online · OpenAI Whisper")
        XCTAssertEqual(status.panelSubtitle, "Über Server verarbeitet · Groq-Kontingent aufgebraucht, jetzt OpenAI Whisper.")
    }

    private var localStatus: TranscriptionModeStatus {
        TranscriptionModeStatus(
            secureLocalModeEnabled: true,
            selectedLocalModelInstalled: true,
            selectedLocalModelDisplayName: "Whisper Turbo",
            isDownloadingLocalModel: false,
            localModelDownloadStatusText: nil,
            hasGroqKey: true,
            groqFallbackActive: false,
            groqQuotaUsedToday: "5 min"
        )
    }

    private func remoteStatus(hasGroqKey: Bool, groqFallbackActive: Bool) -> TranscriptionModeStatus {
        TranscriptionModeStatus(
            secureLocalModeEnabled: false,
            selectedLocalModelInstalled: false,
            selectedLocalModelDisplayName: "Whisper Turbo",
            isDownloadingLocalModel: false,
            localModelDownloadStatusText: nil,
            hasGroqKey: hasGroqKey,
            groqFallbackActive: groqFallbackActive,
            groqQuotaUsedToday: "5 min"
        )
    }
}
