import XCTest
@testable import Turbotext

@MainActor
final class TranscriptionWorkflowTests: XCTestCase {
    func testStopTranscribesThroughSpokenPipelineAndEmitsOutput() async throws {
        let audioURL = try makeTemporaryAudioFile()
        let recorder = FakeTranscriptionRecorder(isRecording: true, duration: 1.0, recordingURL: audioURL)
        let workflow = makeWorkflow(recorder: recorder, transcribe: { _, _, _, _ in " Hallo Welt " })

        var output: String?
        let outputReady = expectation(description: "output")
        workflow.onOutput = { text in
            output = text
            outputReady.fulfill()
        }

        workflow.stop()

        await fulfillment(of: [outputReady], timeout: 1)
        XCTAssertEqual(output, "Hallo Welt")
        XCTAssertEqual(workflow.phase, .done("Hallo Welt"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: audioURL.path))
    }

    func testStopWithoutActiveRecordingCancelsAndResetsToIdle() {
        let recorder = FakeTranscriptionRecorder(isRecording: false, duration: 0, recordingURL: nil)
        let workflow = makeWorkflow(recorder: recorder, transcribe: { _, _, _, _ in "unused" })

        workflow.stop()

        XCTAssertEqual(workflow.phase, .idle)
    }

    /// Regression test: cancelling while transcription is in flight must leave `phase`
    /// at `.idle`, not get overwritten by a late-arriving `.done` once the in-flight
    /// transcriber call eventually returns.
    func testCancellationDuringTranscriptionStaysIdle() async throws {
        let audioURL = try makeTemporaryAudioFile()
        let recorder = FakeTranscriptionRecorder(isRecording: true, duration: 1.0, recordingURL: audioURL)
        let transcriptionStarted = expectation(description: "transcription started")
        let finishTranscription = AsyncGate()

        let workflow = makeWorkflow(recorder: recorder, transcribe: { _, _, _, _ in
            transcriptionStarted.fulfill()
            await finishTranscription.wait()
            return "Hallo Welt"
        })

        workflow.stop()
        await fulfillment(of: [transcriptionStarted], timeout: 1)
        workflow.stop()
        XCTAssertEqual(workflow.phase, .idle)

        await finishTranscription.open()
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(workflow.phase, .idle, "phase must stay .idle, not be overwritten by the late-arriving transcription result")
    }

    func testAudioLevelReflectsPipelineDuringRecording() {
        let recorder = FakeTranscriptionRecorder(isRecording: false, duration: 0, recordingURL: nil)
        recorder.audioLevel = 0.42
        let workflow = makeWorkflow(recorder: recorder, transcribe: { _, _, _, _ in "unused" })

        XCTAssertEqual(workflow.audioLevel, 0.42)
    }

    // MARK: - Helpers

    private func makeWorkflow(
        recorder: FakeTranscriptionRecorder,
        transcribe: @escaping (URL, TimeInterval, [String], String) async throws -> String
    ) -> TranscriptionWorkflow {
        TranscriptionWorkflow(
            type: .transcription,
            customTerms: [],
            language: "de",
            backend: .remote,
            localModelName: "unused",
            pipeline: SpokenWorkflowPipeline(recorder: recorder),
            transcriber: transcribe
        )
    }

    private func makeTemporaryAudioFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("transcription-workflow-\(UUID().uuidString).m4a")
        try Data("audio".utf8).write(to: url)
        return url
    }
}

private final class FakeTranscriptionRecorder: SpokenWorkflowRecording {
    var isRecording: Bool
    var recordingURL: URL?
    var errorMessage: String?
    var audioLevel: Float = 0
    var lastRecordingDuration: TimeInterval

    init(isRecording: Bool, duration: TimeInterval, recordingURL: URL?) {
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
