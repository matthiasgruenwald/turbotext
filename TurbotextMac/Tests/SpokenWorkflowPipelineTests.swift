import XCTest
@testable import Turbotext

@MainActor
final class SpokenWorkflowPipelineTests: XCTestCase {
    /// Deterministic recorder/engine seam (AC #107): a known start failure (no
    /// microphone, Core Audio start error, ...) is injectable via `errorMessage`,
    /// with no dependency on real Core Audio or TCC permissions.
    func testStartRecordingSurfacesKnownRecorderErrorAsFailure() {
        let recorder = FakeSpokenRecorder(isRecording: false)
        recorder.errorMessage = "Kein Mikrofon verfügbar."
        let pipeline = SpokenWorkflowPipeline(recorder: recorder)

        let result = pipeline.startRecording()

        guard case .failure(let error) = result else {
            return XCTFail("expected failure")
        }
        XCTAssertEqual(error.localizedDescription, "Kein Mikrofon verfügbar.")
        XCTAssertEqual(recorder.startCount, 1)
    }

    /// Start -> stop -> start again must work without a real Core Audio engine,
    /// leaving the pipeline free to record again after a stop.
    func testStartStopStartCycleUsesRecorderDeterministically() {
        let recorder = FakeSpokenRecorder(isRecording: false, duration: 1)
        let pipeline = SpokenWorkflowPipeline(recorder: recorder)

        guard case .success = pipeline.startRecording() else { return XCTFail("expected first start to succeed") }
        XCTAssertTrue(pipeline.isRecording)

        recorder.isRecording = false
        XCTAssertEqual(pipeline.stopRecording(), .success(SpokenWorkflowPipeline.Recording(url: recorder.recordingURL!, duration: 1)))

        guard case .success = pipeline.startRecording() else { return XCTFail("expected restart to succeed") }
        XCTAssertTrue(pipeline.isRecording)
        XCTAssertEqual(recorder.startCount, 2)
    }

    func testStopRejectsTooShortRecordingAndDiscardsIt() {
        let recorder = FakeSpokenRecorder(isRecording: true, duration: 0.2)
        let pipeline = SpokenWorkflowPipeline(recorder: recorder)

        let result = pipeline.stopRecording()

        XCTAssertEqual(result, .failure(.noSpeech))
        XCTAssertEqual(recorder.stopCount, 1)
        XCTAssertEqual(recorder.discardCount, 1)
    }

    func testTranscribeSkipsVocabularyHintsForVeryShortAcceptedRecordingAndCleansFile() async throws {
        let audioURL = try makeTemporaryAudioFile()
        let pipeline = SpokenWorkflowPipeline(recorder: FakeSpokenRecorder())
        var receivedTerms: [String]?

        let text = try await pipeline.transcribeRecording(
            SpokenWorkflowPipeline.Recording(url: audioURL, duration: 0.8),
            customTerms: ["Turbotext"],
            language: "de",
            transcriber: { _, _, terms, _ in
                receivedTerms = terms
                return " Hallo "
            }
        )

        XCTAssertEqual(text, "Hallo")
        XCTAssertEqual(receivedTerms, [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: audioURL.path))
    }

    func testTranscribePassesVocabularyHintsForLongEnoughRecording() async throws {
        let audioURL = try makeTemporaryAudioFile()
        let pipeline = SpokenWorkflowPipeline(recorder: FakeSpokenRecorder())
        var receivedTerms: [String]?

        _ = try await pipeline.transcribeRecording(
            SpokenWorkflowPipeline.Recording(url: audioURL, duration: 0.9),
            customTerms: ["Turbotext"],
            language: "de",
            transcriber: { _, _, terms, _ in
                receivedTerms = terms
                return "Hallo"
            }
        )

        XCTAssertEqual(receivedTerms, ["Turbotext"])
    }

    func testTranscribeRejectsArtifactsAndCleansFile() async throws {
        let audioURL = try makeTemporaryAudioFile()
        let pipeline = SpokenWorkflowPipeline(recorder: FakeSpokenRecorder())

        do {
            _ = try await pipeline.transcribeRecording(
                SpokenWorkflowPipeline.Recording(url: audioURL, duration: 0.4),
                customTerms: [],
                language: "de",
                transcriber: { _, _, _, _ in "this is too long for the duration" }
            )
            XCTFail("Expected artifact rejection")
        } catch let error as SpokenWorkflowPipeline.Error {
            XCTAssertEqual(error, .noSpeech)
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: audioURL.path))
    }

    private func makeTemporaryAudioFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("spoken-workflow-\(UUID().uuidString).m4a")
        try Data("audio".utf8).write(to: url)
        return url
    }
}

private final class FakeSpokenRecorder: SpokenWorkflowRecording {
    var isRecording: Bool
    var recordingURL: URL?
    var errorMessage: String?
    var audioLevel: Float = 0
    var lastRecordingDuration: TimeInterval
    var stopCount = 0
    var discardCount = 0
    var startCount = 0

    init(isRecording: Bool = false, duration: TimeInterval = 1, recordingURL: URL? = URL(fileURLWithPath: "/tmp/fake.m4a")) {
        self.isRecording = isRecording
        self.lastRecordingDuration = duration
        self.recordingURL = recordingURL
    }

    func startRecording() {
        startCount += 1
        guard errorMessage == nil else { return }
        isRecording = true
    }

    func stopRecording() {
        stopCount += 1
        isRecording = false
    }

    func discardRecording() {
        discardCount += 1
        recordingURL = nil
    }
}
