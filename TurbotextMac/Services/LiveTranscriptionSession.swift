@preconcurrency import AVFAudio
import Foundation
import Observation
import Speech

@available(macOS 26, *)
@Observable
final class LiveTranscriptionSession {
    enum Phase: Equatable {
        case idle
        case running
        case finished
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var collector = LiveTranscriptCollector()

    var volatileText: String { collector.volatileText }
    var finalText: String { collector.finalText }
    var displayText: String { collector.displayText }

    private var analyzer: SpeechAnalyzer?
    private var transcriber: DictationTranscriber?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var collectingTask: Task<Void, Never>?
    private var converter: AVAudioConverter?

    var isRunning: Bool { phase == .running }

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
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    self.collector.apply(text: text, isFinal: result.isFinal)
                }
                self.phase = .finished
            } catch is CancellationError {
                self.phase = .finished
            } catch {
                if self.phase == .running {
                    self.phase = .failed(error.localizedDescription)
                }
            }
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
