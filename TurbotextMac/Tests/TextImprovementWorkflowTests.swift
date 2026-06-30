import XCTest
@testable import Turbotext

@MainActor
final class TextImprovementWorkflowTests: XCTestCase {
    func testStopTranscribesThroughSpokenPipelineBeforeImproving() async throws {
        let audioURL = try makeTemporaryAudioFile()
        let recorder = FakeTextImprovementRecorder(isRecording: true, duration: 1.0, recordingURL: audioURL)
        var settings = TextImprovementSettings()
        settings.customTerms = ["Turbotext"]

        var transcriptionTerms: [String]?
        var transcriptionLanguage: String?
        var improvedInput: String?
        var output: String?
        let outputReady = expectation(description: "improved output")

        let workflow = TextImprovementWorkflow(
            settings: settings,
            language: "de",
            providerMode: .immerOpenAI,
            pipeline: SpokenWorkflowPipeline(recorder: recorder),
            transcriber: { url, duration, terms, language in
                XCTAssertEqual(url, audioURL)
                XCTAssertEqual(duration, 1.0)
                transcriptionTerms = terms
                transcriptionLanguage = language
                return " Rohtext "
            },
            improver: { text, _, _ in
                improvedInput = text
                return " Verbesserter Text "
            }
        )
        workflow.onOutput = { text in
            output = text
            outputReady.fulfill()
        }

        workflow.stop()

        await fulfillment(of: [outputReady], timeout: 1)
        XCTAssertEqual(transcriptionTerms, ["Turbotext"])
        XCTAssertEqual(transcriptionLanguage, "de")
        XCTAssertEqual(improvedInput, "Rohtext")
        XCTAssertEqual(output, "Verbesserter Text")
        XCTAssertEqual(workflow.phase, .done("Verbesserter Text"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: audioURL.path))
    }

    private func makeTemporaryAudioFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("text-improvement-workflow-\(UUID().uuidString).m4a")
        try Data("audio".utf8).write(to: url)
        return url
    }
}

private final class FakeTextImprovementRecorder: SpokenWorkflowRecording {
    var isRecording: Bool
    var recordingURL: URL?
    var errorMessage: String?
    var audioLevel: Float = 0
    var lastRecordingDuration: TimeInterval

    init(isRecording: Bool, duration: TimeInterval, recordingURL: URL) {
        self.isRecording = isRecording
        self.lastRecordingDuration = duration
        self.recordingURL = recordingURL
    }

    func startRecording() {
        isRecording = true
    }

    func stopRecording() {
        isRecording = false
    }

    func discardRecording() {
        recordingURL = nil
    }
}
