@preconcurrency import AVFAudio
import Foundation
import Observation
import OSLog
import Speech

private let liveLogger = Logger(subsystem: "app.turbotext.mac", category: "LiveDictation")

struct TranscriptionChunk: Sendable, Equatable {
    let text: String
    let isFinal: Bool
}

@available(macOS 26, *)
@Observable
final class LiveTranscriptionSession {
    enum Phase: Equatable {
        case idle
        case running
        case finished
        case failed(String, isBergung: Bool = false)
    }

    var phase: Phase = .idle
    private(set) var collector = LiveTranscriptCollector()

    var volatileText: String { collector.volatileText }
    var finalText: String { collector.finalText }
    var displayText: String { collector.displayText }

    private let availabilityProvider: @Sendable () async -> AppleSpeechAvailabilityStatus
    private let startAssetInstallation: @Sendable () -> Void

    /// The provider is injectable because the real asset status is flaky on some
    /// machines (#177); tests pin it to exercise the early-check path deterministically.
    /// `startAssetInstallation` delegates to the Sprachasset-Bereitschaft module's
    /// `ensureAssetsReady()` (#189) and is wired to `AppState` in production so the
    /// session itself stays free of app state and doesn't decide installability itself.
    init(
        availabilityProvider: @escaping @Sendable () async -> AppleSpeechAvailabilityStatus = {
            await AppleSpeechTranscriptionService.availabilityStatus
        },
        startAssetInstallation: @escaping @Sendable () -> Void = {}
    ) {
        self.availabilityProvider = availabilityProvider
        self.startAssetInstallation = startAssetInstallation
    }

    private var analyzer: SpeechAnalyzer?
    private var transcriber: DictationTranscriber?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var collectingTask: Task<Void, Never>?
    var progressProbeTask: Task<Void, Never>?
    private var converter: AVAudioConverter?

    private static let feedLogInterval = 50
    /// Comfortably above the 10 s drain deadline so the probe outlives a full drain.
    private static let drainProbeLimit: Duration = .seconds(15)
    /// Matches the pill's poll cadence so the progress marker tracks the engine
    /// smoothly instead of jumping once per second (#158 package 4).
    private static let progressProbeInterval: Duration = .milliseconds(100)
    private static let progressProbeLogStride = 10

    @ObservationIgnored private var fedBufferCount = 0
    @ObservationIgnored private var droppedBufferCount = 0
    @ObservationIgnored private var fedAudioSeconds: Double = 0
    @ObservationIgnored private var lastVolatileEndSeconds: Double?
    @ObservationIgnored private var isFinishRequested = false
    @ObservationIgnored private var lastChunkAt: Date?

    var isRunning: Bool { phase == .running }

    /// Seconds of fed audio the engine has not decoded yet (#158 package 4):
    /// fed audio seconds minus `volatileRange.end`. `nil` until the engine reports
    /// its first volatile range, so the waveform stays single-colored before that.
    var transcriptionLag: TimeInterval? {
        Self.transcriptionLag(fedSeconds: fedAudioSeconds, volatileEndSeconds: lastVolatileEndSeconds)
    }

    static func transcriptionLag(fedSeconds: Double, volatileEndSeconds: Double?) -> TimeInterval? {
        guard let volatileEndSeconds else { return nil }
        return max(0, fedSeconds - volatileEndSeconds)
    }

    @MainActor
    func runCollectingLoop(_ chunks: AsyncThrowingStream<TranscriptionChunk, Error>) async {
        do {
            for try await chunk in chunks {
                collector.apply(text: chunk.text, isFinal: chunk.isFinal)
            }
            if isFinishRequested {
                liveLogger.info("collecting loop finished (finishRequested=true)")
                phase = .finished
            } else {
                liveLogger.error("results stream ended without finish request — treating as engine abort")
                phase = .failed("Die Spracherkennung wurde unerwartet beendet.", isBergung: !collector.finalText.isEmpty)
            }
        } catch is CancellationError {
            liveLogger.info("collecting loop cancelled")
            phase = .finished
        } catch {
            guard phase == .running else { return }
            liveLogger.error("collecting loop failed: \(error.localizedDescription)")
            phase = .failed(error.localizedDescription, isBergung: !collector.finalText.isEmpty)
        }
    }

    private func makeChunkStream(_ transcriber: DictationTranscriber) -> AsyncThrowingStream<TranscriptionChunk, Error> {
        AsyncThrowingStream { continuation in
            Task { [weak self] in
                var chunkCount = 0
                var finalCount = 0
                do {
                    for try await result in transcriber.results {
                        chunkCount += 1
                        if result.isFinal { finalCount += 1 }
                        let text = String(result.text.characters)
                        self?.lastChunkAt = Date()
                        liveLogger.info(
                            "chunk #\(chunkCount) isFinal=\(result.isFinal) chars=\(text.count)"
                        )
                        continuation.yield(TranscriptionChunk(text: text, isFinal: result.isFinal))
                    }
                    let expected = self?.isFinishRequested ?? true
                    liveLogger.log(
                        level: expected ? .info : .error,
                        "results stream ended (finishRequested=\(expected)) chunks=\(chunkCount) finals=\(finalCount)"
                    )
                    continuation.finish()
                } catch {
                    let nsError = error as NSError
                    liveLogger.error(
                        "results stream failed domain=\(nsError.domain, privacy: .public) code=\(nsError.code) chunks=\(chunkCount) description=\(nsError.localizedDescription, privacy: .public)"
                    )
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func start(sourceFormat: AVAudioFormat) async throws {
        guard phase == .idle else { return }

        // Without assets the engine silently consumes audio and delivers zero
        // chunks, ending in a misleading "Keine Aufnahme erkannt." (#177).
        let availability = await availabilityProvider()
        guard availability.isAvailable else {
            liveLogger.error(
                "live session refused to start, apple speech availability=\(String(describing: availability), privacy: .public)"
            )
            if availability.isAssetInstallationPossible {
                startAssetInstallation()
            }
            phase = .failed(AppleSpeechUnavailableHint.refusalText(for: availability))
            return
        }

        let transcriber = AppleSpeechTranscriptionService.makeDictationTranscriber(frequentFinalization: true)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            phase = .failed("Audioformat-Erkennung fehlgeschlagen.")
            return
        }

        guard let converter = AVAudioConverter(from: sourceFormat, to: analyzerFormat) else {
            phase = .failed("Audioformat-Konvertierung nicht möglich.")
            return
        }

        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()

        self.transcriber = transcriber
        self.analyzer = analyzer
        self.inputContinuation = continuation
        self.converter = converter
        self.phase = .running

        collectingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.runCollectingLoop(self.makeChunkStream(transcriber))
        }

        let reporting = DictationTranscriber.Preset.progressiveLongDictation.reportingOptions
            .union([.frequentFinalization])
        liveLogger.info(
            """
            session started source=\(sourceFormat.sampleRate)Hz/\(sourceFormat.channelCount)ch \
            analyzer=\(analyzerFormat.sampleRate)Hz/\(analyzerFormat.channelCount)ch \
            volatileResults=\(reporting.contains(.volatileResults)) \
            frequentFinalization=\(reporting.contains(.frequentFinalization))
            """
        )
        startProgressProbe(analyzer: analyzer)

        Task { [weak self] in
            do {
                try await analyzer.start(inputSequence: stream)
                liveLogger.info("analyzer.start returned")
            } catch {
                let nsError = error as NSError
                liveLogger.error("analyzer.start failed domain=\(nsError.domain) code=\(nsError.code)")
                await MainActor.run {
                    guard let self, self.phase == .running else { return }
                    self.phase = .failed(error.localizedDescription)
                }
            }
        }
    }

    nonisolated func feed(buffer: AVAudioPCMBuffer) {
        guard let converter, let continuation = inputContinuation else {
            recordDroppedBuffer(reason: "no converter or continuation")
            return
        }
        let frameCapacity = AVAudioFrameCount(
            Double(buffer.frameLength) * (converter.outputFormat.sampleRate / converter.inputFormat.sampleRate)
        )
        guard frameCapacity > 0,
              let converted = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: frameCapacity)
        else {
            recordDroppedBuffer(reason: "output buffer allocation failed")
            return
        }

        var error: NSError?
        var hasData = true
        converter.convert(to: converted, error: &error) { _, outStatus in
            if hasData {
                hasData = false
                outStatus.pointee = .haveData
                return buffer
            }
            outStatus.pointee = .noDataNow
            return nil
        }
        guard error == nil, converted.frameLength > 0 else {
            recordDroppedBuffer(reason: "convert failed code=\(error?.code ?? 0) frames=\(converted.frameLength)")
            return
        }
        continuation.yield(AnalyzerInput(buffer: converted))
        recordFedBuffer(
            inputFrames: buffer.frameLength,
            outputFrames: converted.frameLength,
            duration: Double(buffer.frameLength) / buffer.format.sampleRate
        )
    }

    /// Diagnose für #155: trennt „Engine steht" von „Audio kommt nicht mehr an",
    /// indem gefütterte Buffer und der Fortschritt des Analyzers gemeinsam getickt werden.
    /// Läuft seit #158 über `finish()` hinaus weiter, damit der Drain protokolliert ist.
    /// Tickt mit 10 Hz, weil `volatileRange.end` dabei die Quelle des
    /// Fortschritts-Markers in der Wellenform ist (#158 Paket 4); die Log-Zeile
    /// bleibt 1 Hz.
    private func startProgressProbe(analyzer: SpeechAnalyzer) {
        progressProbeTask = Task { [weak self] in
            var drainObservedFor: Duration = .zero
            var ticksSinceLog = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.progressProbeInterval)
                guard let self, self.phase == .running else { return }
                if self.isFinishRequested {
                    // Bound the post-finish window so a hung engine cannot probe forever.
                    drainObservedFor += Self.progressProbeInterval
                    if drainObservedFor > Self.drainProbeLimit { return }
                }
                let range = await analyzer.volatileRange
                if let end = range?.end.seconds { self.lastVolatileEndSeconds = end }
                ticksSinceLog += 1
                guard ticksSinceLog >= Self.progressProbeLogStride else { continue }
                ticksSinceLog = 0
                let start = range.map { $0.start.seconds } ?? .nan
                let end = range.map { $0.end.seconds } ?? .nan
                let chunkAge = self.lastChunkAt.map { Date().timeIntervalSince($0) } ?? -1
                liveLogger.info(
                    "probe fed=\(self.fedBufferCount) dropped=\(self.droppedBufferCount) lastChunkAgo=\(String(format: "%.1f", chunkAge), privacy: .public)s volatileRange=\(start)...\(end) finishRequested=\(self.isFinishRequested)"
                )
            }
        }
    }

    private nonisolated func recordFedBuffer(
        inputFrames: AVAudioFrameCount,
        outputFrames: AVAudioFrameCount,
        duration: TimeInterval
    ) {
        fedBufferCount += 1
        fedAudioSeconds += duration
        guard fedBufferCount % Self.feedLogInterval == 0 else { return }
        liveLogger.info(
            "fed \(self.fedBufferCount) buffers (in=\(inputFrames) out=\(outputFrames)) dropped=\(self.droppedBufferCount)"
        )
    }

    private nonisolated func recordDroppedBuffer(reason: String) {
        droppedBufferCount += 1
        guard droppedBufferCount == 1 || droppedBufferCount % Self.feedLogInterval == 0 else { return }
        liveLogger.error("dropped \(self.droppedBufferCount) buffers, last reason: \(reason)")
    }

    func finish() {
        guard phase == .running else { return }
        isFinishRequested = true
        liveLogger.info("finish requested after \(self.fedBufferCount) fed buffers")
        inputContinuation?.finish()
        Task {
            try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        }
    }

    func cancel() {
        guard phase == .running || phase == .idle else { return }
        isFinishRequested = true
        progressProbeTask?.cancel()
        inputContinuation?.finish()
        collectingTask?.cancel()
        Task {
            await analyzer?.cancelAndFinishNow()
        }
        phase = .finished
    }

    @MainActor
    func waitForDrain(timeout: Duration = .seconds(10)) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while phase == .running {
            guard ContinuousClock.now < deadline else { return false }
            do {
                try await Task.sleep(for: .milliseconds(50))
            } catch {
                return false
            }
        }
        return phase == .finished
    }

    func finalizeText() -> String {
        collector.absorbVolatile()
        return collector.finalizedText
    }
}
