import XCTest
@testable import Turbotext

@MainActor
final class RewriteWorkflowPipelineTests: XCTestCase {
    func testDampfAblassenStopTranscribesThroughSpokenPipelineBeforeRewriting() async throws {
        let audioURL = try makeTemporaryAudioFile(prefix: "dampf-ablassen")
        let recorder = FakeRewriteRecorder(isRecording: true, duration: 1.0, recordingURL: audioURL)

        var transcriptionTerms: [String]?
        var transcriptionLanguage: String?
        var rewrittenInput: String?
        var output: String?
        let outputReady = expectation(description: "dampf output")

        let workflow = DampfAblassenWorkflow(
            settings: DampfAblassenSettings(systemPrompt: "Bitte sachlich."),
            customTerms: ["Turbotext"],
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
            rewriter: { text, _, _ in
                rewrittenInput = text
                return " Sachlicher Text "
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
        XCTAssertEqual(rewrittenInput, "Rohtext")
        XCTAssertEqual(output, "Sachlicher Text")
        XCTAssertEqual(workflow.phase, .done("Sachlicher Text"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: audioURL.path))
    }

    func testEmojiStopTranscribesThroughSpokenPipelineBeforeRewriting() async throws {
        let audioURL = try makeTemporaryAudioFile(prefix: "emoji")
        let recorder = FakeRewriteRecorder(isRecording: true, duration: 1.0, recordingURL: audioURL)

        var transcriptionTerms: [String]?
        var transcriptionLanguage: String?
        var rewrittenInput: String?
        var output: String?
        let outputReady = expectation(description: "emoji output")

        let workflow = EmojiTextWorkflow(
            settings: EmojiTextSettings(),
            customTerms: ["Turbotext"],
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
            rewriter: { text, _, _ in
                rewrittenInput = text
                return " Text mit Emoji 🙂 "
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
        XCTAssertEqual(rewrittenInput, "Rohtext")
        XCTAssertEqual(output, "Text mit Emoji 🙂")
        XCTAssertEqual(workflow.phase, .done("Text mit Emoji 🙂"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: audioURL.path))
    }

    func testDampfAblassenCancellationDuringProcessingStaysIdle() async throws {
        let audioURL = try makeTemporaryAudioFile(prefix: "dampf-cancel")
        let recorder = FakeRewriteRecorder(isRecording: true, duration: 1.0, recordingURL: audioURL)
        let transcriptionStarted = expectation(description: "transcription started")
        let finishTranscription = AsyncGate()

        let workflow = DampfAblassenWorkflow(
            settings: DampfAblassenSettings(systemPrompt: "Bitte sachlich."),
            pipeline: SpokenWorkflowPipeline(recorder: recorder),
            transcriber: { _, _, _, _ in
                transcriptionStarted.fulfill()
                await finishTranscription.wait()
                return " Rohtext "
            },
            rewriter: { _, _, _ in
                XCTFail("Cancelled workflow should not rewrite")
                return "ignored"
            }
        )

        workflow.stop()
        await fulfillment(of: [transcriptionStarted], timeout: 1)
        workflow.stop()
        XCTAssertEqual(workflow.phase, .idle)

        await finishTranscription.open()
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(workflow.phase, .idle)
    }

    private func makeTemporaryAudioFile(prefix: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-workflow-\(UUID().uuidString).m4a")
        try Data("audio".utf8).write(to: url)
        return url
    }
}

private final class FakeRewriteRecorder: SpokenWorkflowRecording {
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
