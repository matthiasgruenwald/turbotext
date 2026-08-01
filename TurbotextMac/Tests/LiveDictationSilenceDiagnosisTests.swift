import AVFAudio
import Speech
import XCTest
@testable import Turbotext

/// Diagnose für #155. Fährt den echten Engine-Pfad (Konverter → SpeechAnalyzer →
/// DictationTranscriber) mit vorgefertigtem Audio statt Mikrofon: Sprache, Stille,
/// Sprache. Läuft nur, wenn beide Audiodateien per Environment gesetzt sind —
/// sonst hätte die reguläre Suite eine Abhängigkeit auf lokale Fixtures.
@MainActor
private final class RelayFakeRecorder: SpokenWorkflowRecording {
    var isRecording = false
    var recordingURL: URL? = URL(fileURLWithPath: "/tmp/relay-fake.m4a")
    var errorMessage: String?
    var audioLevel: Float = 0
    var hasUsableSignal = true
    var lastRecordingDuration: TimeInterval = 1
    var inputFormat: AVAudioFormat? = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)
    var onBuffer: (@Sendable (AVAudioPCMBuffer) -> Void)?

    func startRecording() { isRecording = true }
    func stopRecording() { isRecording = false }
    func discardRecording() { recordingURL = nil }
}

@available(macOS 26, *)
@MainActor
final class LiveDictationSilenceDiagnosisTests: XCTestCase {
    private static let tapFrameCount: AVAudioFrameCount = 4096

    private var silenceSeconds: Double {
        ProcessInfo.processInfo.environment["TURBOTEXT_SILENCE_SECONDS"].flatMap(Double.init) ?? 5.0
    }

    /// Echtes Mikrofon liefert nie exakte Nullen; mit Grundrauschen verhält sich
    /// eine VAD womöglich anders als mit digitaler Stille.
    private var noiseAmplitude: Float {
        ProcessInfo.processInfo.environment["TURBOTEXT_NOISE_AMPLITUDE"].flatMap(Float.init) ?? 0
    }

    func testTranscriptGrowsAfterSilenceGap() async throws {
        guard let firstPath = ProcessInfo.processInfo.environment["TURBOTEXT_LIVE_AUDIO_1"],
              let secondPath = ProcessInfo.processInfo.environment["TURBOTEXT_LIVE_AUDIO_2"]
        else {
            throw XCTSkip("TURBOTEXT_LIVE_AUDIO_1/2 nicht gesetzt")
        }

        let transcriber = AppleSpeechTranscriptionService.makeDictationTranscriber()
        let assetStatus = await AssetInventory.status(forModules: [transcriber])
        try XCTSkipUnless(assetStatus == .installed, "Deutsche Sprachassets nicht installiert")

        let first = try loadBuffers(at: firstPath)
        let second = try loadBuffers(at: secondPath)
        let format = first.format

        let session = LiveTranscriptionSession()
        try await session.start(sourceFormat: format)

        await feed(first.buffers, into: session, label: "utterance 1")
        let beforeSilence = session.displayText
        print("[#155] nach Teil 1: \"\(beforeSilence)\"")

        print("[#155] Pause: \(silenceSeconds)s, Rauschamplitude \(noiseAmplitude)")
        await feedSilence(seconds: silenceSeconds, format: format, into: session)
        let afterSilence = session.displayText
        print("[#155] nach \(silenceSeconds)s Stille: \"\(afterSilence)\"")

        await feed(second.buffers, into: session, label: "utterance 2")
        let afterSecond = session.displayText
        print("[#155] nach Teil 2: \"\(afterSecond)\"")
        print("[#155] phase=\(session.phase)")

        XCTAssertFalse(beforeSilence.isEmpty, "Teil 1 wurde nicht erkannt — Harness liefert kein brauchbares Audio")
        XCTAssertGreaterThan(
            afterSecond.count,
            afterSilence.count,
            "Nach der Sprechpause ist kein neuer Text mehr dazugekommen (#155)"
        )
    }

    /// Zweiter Verdacht für #155: nicht die Pause, sondern die Sessiondauer.
    /// Fährt Sprache/Pause im Wechsel, bis der Text nicht mehr wächst.
    func testLongSessionKeepsGrowing() async throws {
        guard let firstPath = ProcessInfo.processInfo.environment["TURBOTEXT_LIVE_AUDIO_1"],
              let secondPath = ProcessInfo.processInfo.environment["TURBOTEXT_LIVE_AUDIO_2"],
              let cycles = ProcessInfo.processInfo.environment["TURBOTEXT_CYCLES"].flatMap(Int.init)
        else {
            throw XCTSkip("TURBOTEXT_LIVE_AUDIO_1/2 und TURBOTEXT_CYCLES nicht gesetzt")
        }

        let transcriber = AppleSpeechTranscriptionService.makeDictationTranscriber()
        let assetStatus = await AssetInventory.status(forModules: [transcriber])
        try XCTSkipUnless(assetStatus == .installed, "Deutsche Sprachassets nicht installiert")

        let first = try loadBuffers(at: firstPath)
        let second = try loadBuffers(at: secondPath)
        let session = LiveTranscriptionSession()
        try await session.start(sourceFormat: first.format)

        var previousLength = 0
        for cycle in 1...cycles {
            await feed(first.buffers, into: session, label: "cycle \(cycle) a")
            await feedSilence(seconds: silenceSeconds, format: first.format, into: session)
            await feed(second.buffers, into: session, label: "cycle \(cycle) b")
            await feedSilence(seconds: silenceSeconds, format: first.format, into: session)

            let length = session.displayText.count
            let grew = length > previousLength
            print("[#155] Zyklus \(cycle): chars=\(length) gewachsen=\(grew) final=\(session.finalText.count) phase=\(session.phase)")
            if !grew {
                print("[#155] STOPP in Zyklus \(cycle) — Text wächst nicht mehr. Letzter Text: \"\(session.displayText.suffix(120))\"")
                XCTFail("Transkript ist in Zyklus \(cycle) eingefroren (#155)")
                return
            }
            previousLength = length
        }
        print("[#155] \(cycles) Zyklen ohne Einfrieren durchlaufen")
    }

    /// Dritter Verdacht für #155: nicht die Engine, sondern die Anzeige-Kette.
    /// `LiveDictationWorkflow.observeSession` nutzt einmalig feuerndes
    /// `withObservationTracking` und registriert sich erst nach einem Task-Hop neu —
    /// Updates in diesem Fenster können verloren gehen.
    func testEveryTranscriptUpdateReachesTheDisplay() async throws {
        let session = LiveTranscriptionSession(smoothing: PassthroughSmoothing())
        let recorder = RelayFakeRecorder()
        var relayed: [String] = []
        let workflow = LiveDictationWorkflow(
            type: .transcription,
            session: session,
            pipeline: SpokenWorkflowPipeline(recorder: recorder),
            onLiveTranscriptUpdate: { display in
                relayed.append(display.finalText + display.volatileText)
            }
        )
        workflow.start()

        let updateCount = 20
        let (stream, continuation) = AsyncThrowingStream<TranscriptionChunk, Error>.makeStream()
        let loop = Task { await session.runCollectingLoop(stream) }
        for index in 1...updateCount {
            continuation.yield(TranscriptionChunk(text: String(repeating: "x", count: index), isFinal: false))
            try await Task.sleep(for: .milliseconds(20))
        }
        continuation.finish()
        await loop.value

        try await Task.sleep(for: .milliseconds(200))
        print("[#155] Updates gesendet=\(updateCount) relayed=\(relayed.count)")
        print("[#155] letzter relayed=\"\(relayed.last ?? "")\" session=\"\(session.displayText)\"")
        XCTAssertEqual(
            relayed.last,
            session.displayText,
            "Die Pille zeigt nicht den aktuellen Stand — Anzeige-Kette verliert Updates (#155)"
        )
    }

    private func feed(
        _ buffers: [AVAudioPCMBuffer],
        into session: LiveTranscriptionSession,
        label: String
    ) async {
        for buffer in buffers {
            session.feed(buffer: buffer)
            try? await Task.sleep(for: .milliseconds(realTimeChunkMilliseconds(buffer)))
        }
        print("[#155] \(label) gefüttert: \(buffers.count) Buffer")
    }

    private func feedSilence(
        seconds: Double,
        format: AVAudioFormat,
        into session: LiveTranscriptionSession
    ) async {
        let chunkCount = Int((seconds * format.sampleRate / Double(Self.tapFrameCount)).rounded())
        let amplitude = noiseAmplitude
        for _ in 0..<chunkCount {
            guard let silence = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: Self.tapFrameCount) else { continue }
            silence.frameLength = Self.tapFrameCount
            if amplitude > 0, let channel = silence.floatChannelData {
                for frame in 0..<Int(silence.frameLength) {
                    channel[0][frame] = Float.random(in: -amplitude...amplitude)
                }
            }
            session.feed(buffer: silence)
            try? await Task.sleep(for: .milliseconds(realTimeChunkMilliseconds(silence)))
        }
    }

    private func realTimeChunkMilliseconds(_ buffer: AVAudioPCMBuffer) -> Int {
        Int(Double(buffer.frameLength) / buffer.format.sampleRate * 1000)
    }

    private func loadBuffers(at path: String) throws -> (format: AVAudioFormat, buffers: [AVAudioPCMBuffer]) {
        let file = try AVAudioFile(forReading: URL(fileURLWithPath: path))
        let format = file.processingFormat
        var buffers: [AVAudioPCMBuffer] = []
        while file.framePosition < file.length {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: Self.tapFrameCount) else { break }
            try file.read(into: buffer, frameCount: Self.tapFrameCount)
            guard buffer.frameLength > 0 else { break }
            buffers.append(buffer)
        }
        return (format, buffers)
    }
}
