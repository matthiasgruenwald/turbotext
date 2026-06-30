import XCTest
@testable import Turbotext

@MainActor
final class SpokenWorkflowPipelineTests: XCTestCase {
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

    init(isRecording: Bool = false, duration: TimeInterval = 1, recordingURL: URL? = URL(fileURLWithPath: "/tmp/fake.m4a")) {
        self.isRecording = isRecording
        self.lastRecordingDuration = duration
        self.recordingURL = recordingURL
    }

    func startRecording() {
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
