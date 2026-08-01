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

    private let smoothing: any LiveSmoothing
    private var analyzer: SpeechAnalyzer?
    private var transcriber: DictationTranscriber?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var collectingTask: Task<Void, Never>?
    private var progressProbeTask: Task<Void, Never>?
    private var converter: AVAudioConverter?

    private static let feedLogInterval = 50

    @ObservationIgnored private var fedBufferCount = 0
    @ObservationIgnored private var droppedBufferCount = 0
    @ObservationIgnored private var isFinishRequested = false
    @ObservationIgnored private var lastChunkAt: Date?

    var isRunning: Bool { phase == .running }

    init(smoothing: any LiveSmoothing = PassthroughSmoothing()) {
        self.smoothing = smoothing
    }

    @MainActor
    func runCollectingLoop(_ chunks: AsyncThrowingStream<TranscriptionChunk, Error>) async {
        var lastFinalSegment = ""
        do {
            for try await chunk in chunks {
                if chunk.isFinal {
                    let context = LiveSmoothingContext.tail(of: lastFinalSegment)
                    let smoothed = await smoothing.smooth(segment: chunk.text, context: context)
                    let final = smoothed ?? chunk.text
                    collector.apply(text: final, isFinal: true)
                    lastFinalSegment = final
                } else {
                    collector.apply(text: chunk.text, isFinal: false)
                }
            }
            liveLogger.info("collecting loop finished (finishRequested=\(self.isFinishRequested))")
            phase = .finished
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
        recordFedBuffer(inputFrames: buffer.frameLength, outputFrames: converted.frameLength)
    }

    /// Diagnose für #155: trennt „Engine steht" von „Audio kommt nicht mehr an",
    /// indem gefütterte Buffer und der Fortschritt des Analyzers gemeinsam getickt werden.
    private func startProgressProbe(analyzer: SpeechAnalyzer) {
        progressProbeTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, self.phase == .running else { return }
                let range = await analyzer.volatileRange
                let start = range.map { $0.start.seconds } ?? .nan
                let end = range.map { $0.end.seconds } ?? .nan
                let chunkAge = self.lastChunkAt.map { Date().timeIntervalSince($0) } ?? -1
                liveLogger.info(
                    "probe fed=\(self.fedBufferCount) dropped=\(self.droppedBufferCount) lastChunkAgo=\(String(format: "%.1f", chunkAge), privacy: .public)s volatileRange=\(start)...\(end)"
                )
            }
        }
    }

    private nonisolated func recordFedBuffer(inputFrames: AVAudioFrameCount, outputFrames: AVAudioFrameCount) {
        fedBufferCount += 1
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
        progressProbeTask?.cancel()
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

    func finalizeText() -> String {
        collector.absorbVolatile()
        return collector.finalizedText
    }
}
