import AVFAudio
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

        let workflow = SpokenRewriteWorkflow.textImprovement(
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
                return RewriteStepResult(text: " Verbesserter Text ", completionLabel: nil)
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

    /// Regression test: cancelling while the improve step (not the transcription step)
    /// is in flight must leave `phase` at `.idle`, not get overwritten by a late-arriving
    /// `.done` once the in-flight improver call eventually returns.
    func testCancellationDuringImprovingStaysIdle() async throws {
        let audioURL = try makeTemporaryAudioFile()
        let recorder = FakeTextImprovementRecorder(isRecording: true, duration: 1.0, recordingURL: audioURL)
        let improveStarted = expectation(description: "improve started")
        let finishImprove = AsyncGate()

        let workflow = SpokenRewriteWorkflow.textImprovement(
            settings: TextImprovementSettings(),
            pipeline: SpokenWorkflowPipeline(recorder: recorder),
            transcriber: { _, _, _, _ in " Rohtext " },
            improver: { _, _, _ in
                improveStarted.fulfill()
                await finishImprove.wait()
                return RewriteStepResult(text: "Verbesserter Text", completionLabel: nil)
            }
        )

        workflow.stop()
        await fulfillment(of: [improveStarted], timeout: 1)
        workflow.stop()
        XCTAssertEqual(workflow.phase, .idle)

        await finishImprove.open()
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(workflow.phase, .idle, "phase must stay .idle, not be overwritten by the late-arriving improve result")
    }

    private func makeTemporaryAudioFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("text-improvement-workflow-\(UUID().uuidString).m4a")
        try Data("audio".utf8).write(to: url)
        return url
    }
}

private actor AsyncGate {
    private var isOpen = false
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen {
            return
        }
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func open() {
        isOpen = true
        continuations.forEach { $0.resume() }
        continuations = []
    }
}

private final class FakeTextImprovementRecorder: SpokenWorkflowRecording {
    var isRecording: Bool
    var recordingURL: URL?
    var errorMessage: String?
    var audioLevel: Float = 0
    var lastRecordingDuration: TimeInterval
    var inputFormat: AVAudioFormat?
    var onBuffer: (@Sendable (AVAudioPCMBuffer) -> Void)?

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
