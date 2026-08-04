import AVFAudio
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

        let workflow = SpokenRewriteWorkflow.dampfAblassen(
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
                return RewriteStepResult(text: " Sachlicher Text ", completionLabel: nil)
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

        let workflow = SpokenRewriteWorkflow.emojiText(
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
                return RewriteStepResult(text: " Text mit Emoji 🙂 ", completionLabel: nil)
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

        let workflow = SpokenRewriteWorkflow.dampfAblassen(
            settings: DampfAblassenSettings(systemPrompt: "Bitte sachlich."),
            pipeline: SpokenWorkflowPipeline(recorder: recorder),
            transcriber: { _, _, _, _ in
                transcriptionStarted.fulfill()
                await finishTranscription.wait()
                return " Rohtext "
            },
            rewriter: { _, _, _ in
                XCTFail("Cancelled workflow should not rewrite")
                return RewriteStepResult(text: "ignored", completionLabel: nil)
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

    /// Regression test: cancelling while the rewrite step (not the transcription step)
    /// is in flight must leave `phase` at `.idle`. Previously, the workflow only checked
    /// `Task.checkCancellation()` once, right after transcription; if `stop()` cancelled
    /// the task while an in-flight rewrite call was still running, the task would ignore
    /// the cancellation and overwrite the freshly-reset `.idle` phase with `.done` once
    /// the rewrite call eventually returned.
    func testDampfAblassenCancellationDuringRewriteStaysIdle() async throws {
        let audioURL = try makeTemporaryAudioFile(prefix: "dampf-cancel-rewrite")
        let recorder = FakeRewriteRecorder(isRecording: true, duration: 1.0, recordingURL: audioURL)
        let rewriteStarted = expectation(description: "rewrite started")
        let finishRewrite = AsyncGate()

        let workflow = SpokenRewriteWorkflow.dampfAblassen(
            settings: DampfAblassenSettings(systemPrompt: "Bitte sachlich."),
            pipeline: SpokenWorkflowPipeline(recorder: recorder),
            transcriber: { _, _, _, _ in " Rohtext " },
            rewriter: { _, _, _ in
                rewriteStarted.fulfill()
                await finishRewrite.wait()
                return RewriteStepResult(text: "Sachlicher Text", completionLabel: nil)
            }
        )

        workflow.stop()
        await fulfillment(of: [rewriteStarted], timeout: 1)
        workflow.stop()
        XCTAssertEqual(workflow.phase, .idle)

        await finishRewrite.open()
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(workflow.phase, .idle, "phase must stay .idle, not be overwritten by the late-arriving rewrite result")
    }

    func testEmojiCancellationDuringRewriteStaysIdle() async throws {
        let audioURL = try makeTemporaryAudioFile(prefix: "emoji-cancel-rewrite")
        let recorder = FakeRewriteRecorder(isRecording: true, duration: 1.0, recordingURL: audioURL)
        let rewriteStarted = expectation(description: "rewrite started")
        let finishRewrite = AsyncGate()

        let workflow = SpokenRewriteWorkflow.emojiText(
            settings: EmojiTextSettings(),
            pipeline: SpokenWorkflowPipeline(recorder: recorder),
            transcriber: { _, _, _, _ in " Rohtext " },
            rewriter: { _, _, _ in
                rewriteStarted.fulfill()
                await finishRewrite.wait()
                return RewriteStepResult(text: "Text mit Emoji 🙂", completionLabel: nil)
            }
        )

        workflow.stop()
        await fulfillment(of: [rewriteStarted], timeout: 1)
        workflow.stop()
        XCTAssertEqual(workflow.phase, .idle)

        await finishRewrite.open()
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(workflow.phase, .idle, "phase must stay .idle, not be overwritten by the late-arriving rewrite result")
    }

    // MARK: - Raw insertion of very short transcripts (#173)

    func testDampfAblassenShortTranscriptSkipsRewriterAndInsertsRaw() async throws {
        let audioURL = try makeTemporaryAudioFile(prefix: "dampf-raw")
        let recorder = FakeRewriteRecorder(isRecording: true, duration: 1.0, recordingURL: audioURL)
        let outputReady = expectation(description: "raw output")
        var rewriterCalled = false
        var output: String?

        let workflow = SpokenRewriteWorkflow.dampfAblassen(
            settings: DampfAblassenSettings(systemPrompt: "Bitte sachlich."),
            pipeline: SpokenWorkflowPipeline(recorder: recorder),
            transcriber: { _, _, _, _ in "Mist" },
            rewriter: { _, _, _ in
                rewriterCalled = true
                return RewriteStepResult(text: "ignored", completionLabel: nil)
            }
        )
        workflow.onOutput = { text in
            output = text
            outputReady.fulfill()
        }

        workflow.stop()

        await fulfillment(of: [outputReady], timeout: 1)
        XCTAssertFalse(rewriterCalled)
        XCTAssertEqual(output, "Mist")
        XCTAssertEqual(workflow.phase, .done("Mist"))
        XCTAssertEqual(workflow.completionLabel, "Sehr kurze Eingabe – ohne Nachbearbeitung eingefügt")
    }

    func testEmojiShortTranscriptSkipsRewriterAndInsertsRaw() async throws {
        let audioURL = try makeTemporaryAudioFile(prefix: "emoji-raw")
        let recorder = FakeRewriteRecorder(isRecording: true, duration: 1.0, recordingURL: audioURL)
        let outputReady = expectation(description: "raw output")
        var rewriterCalled = false
        var output: String?

        let workflow = SpokenRewriteWorkflow.emojiText(
            settings: EmojiTextSettings(),
            pipeline: SpokenWorkflowPipeline(recorder: recorder),
            transcriber: { _, _, _, _ in "Ok" },
            rewriter: { _, _, _ in
                rewriterCalled = true
                return RewriteStepResult(text: "ignored", completionLabel: nil)
            }
        )
        workflow.onOutput = { text in
            output = text
            outputReady.fulfill()
        }

        workflow.stop()

        await fulfillment(of: [outputReady], timeout: 1)
        XCTAssertFalse(rewriterCalled)
        XCTAssertEqual(output, "Ok")
        XCTAssertEqual(workflow.phase, .done("Ok"))
        XCTAssertEqual(workflow.completionLabel, "Sehr kurze Eingabe – ohne Nachbearbeitung eingefügt")
    }

    // MARK: - Processing label (#128)

    /// Regression: `processingLabel` must already hold its resolved value by the time
    /// `onPhaseChange` fires for the rewrite `.running` phase — `WorkflowOrchestrator`
    /// reads it synchronously from within that same callback.
    func testProcessingLabelIsResolvedBeforeTheRewritePhaseChangeFires() async throws {
        let audioURL = try makeTemporaryAudioFile(prefix: "dampf-processing-label")
        let recorder = FakeRewriteRecorder(isRecording: true, duration: 1.0, recordingURL: audioURL)
        let outputReady = expectation(description: "output")
        var observedLabelDuringRewritePhase: String??

        let workflow = SpokenRewriteWorkflow.dampfAblassen(
            settings: DampfAblassenSettings(systemPrompt: "Bitte sachlich."),
            pipeline: SpokenWorkflowPipeline(recorder: recorder),
            transcriber: { _, _, _, _ in "Rohtext" },
            processingLabelResolver: { "Nachbearbeitung läuft – lokal auf diesem Mac" },
            rewriter: { text, _, _ in RewriteStepResult(text: text, completionLabel: nil) }
        )
        workflow.onPhaseChange = { phase in
            if case .running("Wird umformuliert ...") = phase {
                observedLabelDuringRewritePhase = workflow.processingLabel
            }
        }
        workflow.onOutput = { _ in outputReady.fulfill() }

        workflow.stop()

        await fulfillment(of: [outputReady], timeout: 1)
        XCTAssertEqual(observedLabelDuringRewritePhase, "Nachbearbeitung läuft – lokal auf diesem Mac")
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
