@preconcurrency import AVFAudio
import Foundation
import Observation
import Speech

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
    private var converter: AVAudioConverter?

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
            phase = .finished
        } catch is CancellationError {
            phase = .finished
        } catch {
            guard phase == .running else { return }
            phase = .failed(error.localizedDescription, isBergung: !collector.finalText.isEmpty)
        }
    }

    private func makeChunkStream(_ transcriber: DictationTranscriber) -> AsyncThrowingStream<TranscriptionChunk, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await result in transcriber.results {
                        continuation.yield(TranscriptionChunk(
                            text: String(result.text.characters),
                            isFinal: result.isFinal
                        ))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func start(sourceFormat: AVAudioFormat) async throws {
        guard phase == .idle else { return }

        let transcriber = AppleSpeechTranscriptionService.makeDictationTranscriber()
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

        Task { [weak self] in
            do {
                try await analyzer.start(inputSequence: stream)
            } catch {
                await MainActor.run {
                    guard let self, self.phase == .running else { return }
                    self.phase = .failed(error.localizedDescription)
                }
            }
        }
    }

    nonisolated func feed(buffer: AVAudioPCMBuffer) {
        guard let converter, let continuation = inputContinuation else { return }
        let frameCapacity = AVAudioFrameCount(
            Double(buffer.frameLength) * (converter.outputFormat.sampleRate / converter.inputFormat.sampleRate)
        )
        guard frameCapacity > 0,
              let converted = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: frameCapacity)
        else { return }

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
        guard error == nil, converted.frameLength > 0 else { return }
        continuation.yield(AnalyzerInput(buffer: converted))
    }

    func finish() {
        guard phase == .running else { return }
        inputContinuation?.finish()
        Task {
            try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        }
    }

    func cancel() {
        guard phase == .running || phase == .idle else { return }
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
