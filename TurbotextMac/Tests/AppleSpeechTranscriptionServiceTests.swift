import AVFAudio
import Speech
import XCTest
@testable import Turbotext

@available(macOS 26, *)
final class AppleSpeechTranscriptionServiceTests: XCTestCase {
    // MARK: - isAvailable (pure decision logic, no real Speech/asset state needed)

    func testIsAvailableFalseWhenOSTooOld() {
        XCTAssertFalse(
            AppleSpeechTranscriptionService.isAvailable(osSupportsAppleSpeech: false, assetStatus: .installed)
        )
    }

    func testIsAvailableFalseWhenAssetsNotInstalled() {
        XCTAssertFalse(
            AppleSpeechTranscriptionService.isAvailable(osSupportsAppleSpeech: true, assetStatus: .supported)
        )
        XCTAssertFalse(
            AppleSpeechTranscriptionService.isAvailable(osSupportsAppleSpeech: true, assetStatus: .unsupported)
        )
        XCTAssertFalse(
            AppleSpeechTranscriptionService.isAvailable(osSupportsAppleSpeech: true, assetStatus: .downloading)
        )
    }

    func testIsAvailableTrueWhenOSSupportedAndAssetsInstalled() {
        XCTAssertTrue(
            AppleSpeechTranscriptionService.isAvailable(osSupportsAppleSpeech: true, assetStatus: .installed)
        )
    }

    func testLiveIsAvailableMatchesRealAssetStatus() async {
        let transcriber = DictationTranscriber(
            locale: AppleSpeechTranscriptionService.locale,
            preset: .progressiveLongDictation
        )
        let status = await AssetInventory.status(forModules: [transcriber])
        let expected = status == .installed

        let actual = await AppleSpeechTranscriptionService.isAvailable
        XCTAssertEqual(actual, expected)
    }

    // MARK: - Error forwarding

    func testAssetsNotInstalledHasGermanErrorDescription() {
        XCTAssertEqual(
            AppleSpeechTranscriptionError.assetsNotInstalled.errorDescription,
            "Deutsche Sprachassets für die Gerätetranskription sind nicht installiert."
        )
    }

    func testCancelledHasGermanErrorDescription() {
        XCTAssertEqual(
            AppleSpeechTranscriptionError.cancelled.errorDescription,
            "Transkription wurde abgebrochen."
        )
    }

    func testTranscriptionFailedWrapsUnderlyingMessage() {
        XCTAssertEqual(
            AppleSpeechTranscriptionError.transcriptionFailed("Sprachfehler xyz").errorDescription,
            "Apple Gerätetranskription ist fehlgeschlagen: Sprachfehler xyz"
        )
    }

    /// On a machine without installed de-DE assets, `transcribe` must fail fast
    /// with `.assetsNotInstalled` before ever touching `AVAudioFile`/`SpeechAnalyzer` —
    /// calling those APIs while assets are only `.supported` aborts the process
    /// (verified against the live Speech framework while building this service).
    func testTranscribeThrowsAssetsNotInstalledWhenAssetsAreMissing() async throws {
        try await Self.skipIfAssetsInstalled()

        do {
            _ = try await AppleSpeechTranscriptionService.transcribe(
                audioURL: URL(fileURLWithPath: "/nonexistent/does-not-matter.wav"),
                duration: 1,
                customTerms: [],
                language: "de"
            )
            XCTFail("expected assetsNotInstalled to be thrown")
        } catch let error as AppleSpeechTranscriptionError {
            XCTAssertEqual(error, .assetsNotInstalled)
        }
    }

    // MARK: - makeTranscriber drop-in wiring

    func testMakeTranscriberProducesPipelineCompatibleClosureAndForwardsErrors() async throws {
        try await Self.skipIfAssetsInstalled()

        let transcriber: SpokenWorkflowPipeline.Transcriber = AppleSpeechTranscriptionService.makeTranscriber()

        do {
            _ = try await transcriber(URL(fileURLWithPath: "/nonexistent/does-not-matter.wav"), 1, ["Fachbegriff"], "de")
            XCTFail("expected assetsNotInstalled to be thrown")
        } catch let error as AppleSpeechTranscriptionError {
            XCTAssertEqual(error, .assetsNotInstalled)
        }
    }

    // MARK: - Real on-device transcription (only runs when de-DE assets are installed)

    func testTranscribesSynthesizedGermanAudioFixture() async throws {
        guard await AppleSpeechTranscriptionService.isAvailable else {
            throw XCTSkip("Deutsche Apple-Sprachassets sind auf diesem Gerät nicht installiert.")
        }

        let audioURL = try await Self.makeGermanSpeechFixture(text: "Hallo, dies ist ein kurzer Test.")
        defer { try? FileManager.default.removeItem(at: audioURL) }

        var partials: [String] = []
        let text = try await AppleSpeechTranscriptionService.transcribe(
            audioURL: audioURL,
            duration: 2,
            customTerms: [],
            language: "de",
            partialTranscriptHandler: { partials.append($0) }
        )

        XCTAssertFalse(text.isEmpty)
        _ = partials // interim results are best-effort; presence isn't guaranteed for very short audio
    }

    /// Both "asset missing" tests below only hold deterministically when de-DE
    /// assets are actually absent on the machine running them.
    private static func skipIfAssetsInstalled() async throws {
        guard await !AppleSpeechTranscriptionService.isAvailable else {
            throw XCTSkip("Deutsche Apple-Sprachassets sind auf diesem Gerät installiert.")
        }
    }

    /// Synthesizes a short German utterance to a temporary audio file using
    /// on-device text-to-speech, so the transcription test doesn't depend on a
    /// checked-in binary audio fixture.
    private static func makeGermanSpeechFixture(text: String) async throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("apple-speech-fixture-\(UUID().uuidString).caf")

        let synthesizer = AVSpeechSynthesizer()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "de-DE")

        final class OutputFileBox: @unchecked Sendable {
            var file: AVAudioFile?
        }
        let outputBox = OutputFileBox()

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var didResume = false
            synthesizer.write(utterance) { buffer in
                guard !didResume else { return }
                guard let pcmBuffer = buffer as? AVAudioPCMBuffer else { return }

                if pcmBuffer.frameLength == 0 {
                    didResume = true
                    continuation.resume()
                    return
                }

                do {
                    if outputBox.file == nil {
                        outputBox.file = try AVAudioFile(forWriting: url, settings: pcmBuffer.format.settings)
                    }
                    try outputBox.file?.write(from: pcmBuffer)
                } catch {
                    didResume = true
                    continuation.resume(throwing: error)
                }
            }
        }

        return url
    }
}
