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

    /// #175: A single leftover character made the on-device model echo the system
    /// prompt back out (which then got pasted). Such fragments must be rejected
    /// before any rewrite model sees them.
    func testSingleCharacterTranscriptIsRejectedBeforeImproving() async throws {
        let audioURL = try makeTemporaryAudioFile()
        let recorder = FakeTextImprovementRecorder(isRecording: true, duration: 1.0, recordingURL: audioURL)
        let done = expectation(description: "workflow settled")
        var improverCalled = false

        let workflow = SpokenRewriteWorkflow.textImprovement(
            settings: TextImprovementSettings(),
            pipeline: SpokenWorkflowPipeline(recorder: recorder),
            transcriber: { _, _, _, _ in "a" },
            improver: { _, _, _ in
                improverCalled = true
                return RewriteStepResult(text: "ignored", completionLabel: nil)
            }
        )
        workflow.onOutput = { _ in
            XCTFail("Single-character fragments must not produce output")
            done.fulfill()
        }
        workflow.onPhaseChange = { phase in
            if case .error = phase { done.fulfill() }
        }

        workflow.stop()

        await fulfillment(of: [done], timeout: 1)
        XCTAssertFalse(improverCalled)
        XCTAssertEqual(workflow.phase, .error("Keine Aufnahme erkannt."))
    }

    /// #173: empty transcripts never reach the rewrite step — the pipeline
    /// rejects them as artifacts and the workflow reports "no recording".
    func testEmptyTranscriptIsRejectedBeforeImproving() async throws {
        let audioURL = try makeTemporaryAudioFile()
        let recorder = FakeTextImprovementRecorder(isRecording: true, duration: 1.0, recordingURL: audioURL)
        let done = expectation(description: "workflow settled")
        var improverCalled = false

        let workflow = SpokenRewriteWorkflow.textImprovement(
            settings: TextImprovementSettings(),
            pipeline: SpokenWorkflowPipeline(recorder: recorder),
            transcriber: { _, _, _, _ in "" },
            improver: { _, _, _ in
                improverCalled = true
                return RewriteStepResult(text: "ignored", completionLabel: nil)
            }
        )
        workflow.onOutput = { _ in
            XCTFail("Empty transcripts must not produce output")
            done.fulfill()
        }
        workflow.onPhaseChange = { phase in
            if case .error = phase { done.fulfill() }
        }

        workflow.stop()

        await fulfillment(of: [done], timeout: 1)
        XCTAssertFalse(improverCalled)
        XCTAssertEqual(workflow.phase, .error("Keine Aufnahme erkannt."))
    }

    /// #173 threshold: five characters are the minimum that may reach the model;
    /// 2–4 characters are inserted raw (#173), below two is rejected (#175).
    func testFiveCharacterTranscriptStillReachesImprover() async throws {
        let audioURL = try makeTemporaryAudioFile()
        let recorder = FakeTextImprovementRecorder(isRecording: true, duration: 1.0, recordingURL: audioURL)
        let outputReady = expectation(description: "improved output")
        var improvedInput: String?

        let workflow = SpokenRewriteWorkflow.textImprovement(
            settings: TextImprovementSettings(),
            pipeline: SpokenWorkflowPipeline(recorder: recorder),
            transcriber: { _, _, _, _ in "Danke" },
            improver: { text, _, _ in
                improvedInput = text
                return RewriteStepResult(text: "Danke.", completionLabel: nil)
            }
        )
        workflow.onOutput = { _ in outputReady.fulfill() }

        workflow.stop()

        await fulfillment(of: [outputReady], timeout: 1)
        XCTAssertEqual(improvedInput, "Danke")
    }

    /// #173: 2–4-character transcripts never made it through the LLM without
    /// prompt-echo hallucinations, so they are inserted raw and skip the
    /// improver entirely.
    func testShortTranscriptIsInsertedRawWithoutImproving() async throws {
        let audioURL = try makeTemporaryAudioFile()
        let recorder = FakeTextImprovementRecorder(isRecording: true, duration: 1.0, recordingURL: audioURL)
        let outputReady = expectation(description: "raw output")
        var improverCalled = false
        var output: String?

        let workflow = SpokenRewriteWorkflow.textImprovement(
            settings: TextImprovementSettings(),
            pipeline: SpokenWorkflowPipeline(recorder: recorder),
            transcriber: { _, _, _, _ in " Nein " },
            improver: { _, _, _ in
                improverCalled = true
                return RewriteStepResult(text: "ignored", completionLabel: nil)
            }
        )
        workflow.onOutput = { text in
            output = text
            outputReady.fulfill()
        }

        workflow.stop()

        await fulfillment(of: [outputReady], timeout: 1)
        XCTAssertFalse(improverCalled)
        XCTAssertEqual(output, "Nein")
        XCTAssertEqual(workflow.phase, .done("Nein"))
        XCTAssertEqual(workflow.completionLabel, "Sehr kurze Eingabe – ohne Nachbearbeitung eingefügt")
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
