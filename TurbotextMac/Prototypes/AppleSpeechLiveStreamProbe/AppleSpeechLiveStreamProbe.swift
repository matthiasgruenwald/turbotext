// PROTOTYPE — measurement harness for GitHub issue #143, not production code.
// Streams a pre-recorded German dictation into SpeechAnalyzer's `start(inputSequence:)`
// at real-time pace (buffer-by-buffer, paced to its own duration) to simulate a live
// microphone tap, and logs volatile/final result behavior, timing, and memory.

import AVFAudio
import Foundation
import Speech

@main
struct AppleSpeechLiveStreamProbe {
    static func main() async {
        guard CommandLine.arguments.count >= 2 else {
            fputs("Usage: AppleSpeechLiveStreamProbe <audio-file> [--frequent-finalization]\n", stderr)
            exit(64)
        }

        let locale = Locale(identifier: "de-DE")
        let probeTranscriber = DictationTranscriber(locale: locale, preset: .progressiveLongDictation)
        var status = await AssetInventory.status(forModules: [probeTranscriber])
        print("asset-status-before=\(status)")
        if status != .installed {
            // Ephemeral per-process install: this unsigned CLI binary has no stable
            // identity/entitlements, so AssetInventory does not persist the install
            // across processes. Installing in-process makes it available for this run.
            do {
                if let request = try await AssetInventory.assetInstallationRequest(supporting: [probeTranscriber]) {
                    try await request.downloadAndInstall()
                }
            } catch {
                fputs("asset-install-error=\(error)\n", stderr)
                exit(69)
            }
            status = await AssetInventory.status(forModules: [probeTranscriber])
        }
        print("asset-status-after=\(status)")
        guard status == .installed else {
            fputs("German dictation assets could not be installed for this run.\n", stderr)
            exit(69)
        }

        let useFrequentFinalization = CommandLine.arguments.contains("--frequent-finalization")
        var options: Set<DictationTranscriber.ReportingOption> = [.volatileResults]
        if ProcessInfo.processInfo.environment["FREQUENT_FINALIZATION"] == "1" || useFrequentFinalization {
            options.insert(.frequentFinalization)
        }

        do {
            try await run(audioPath: CommandLine.arguments[1], locale: locale, options: options)
        } catch {
            fputs("probe-error=\(error)\n", stderr)
            exit(70)
        }
    }

    static func run(audioPath: String, locale: Locale, options: Set<DictationTranscriber.ReportingOption>) async throws {
        print("reporting-options=\(options)")
        let transcriber = DictationTranscriber(
            locale: locale,
            contentHints: [],
            transcriptionOptions: [],
            reportingOptions: options,
            attributeOptions: []
        )
        let analyzer = try SpeechAnalyzer(modules: [transcriber])

        guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            fputs("no-analyzer-format\n", stderr)
            exit(71)
        }
        print("analyzer-format=\(analyzerFormat)")

        let sourceFile = try AVAudioFile(forReading: URL(fileURLWithPath: audioPath))
        let sourceFormat = sourceFile.processingFormat
        guard let converter = AVAudioConverter(from: sourceFormat, to: analyzerFormat) else {
            fputs("no-converter\n", stderr)
            exit(72)
        }

        let (inputSequence, inputBuilder) = AsyncStream<AnalyzerInput>.makeStream()
        try await analyzer.start(inputSequence: inputSequence)

        let clockStart = ContinuousClock.now
        var appendedFinalText = ""
        var overwriteFinalText = ""
        var finalCount = 0
        var volatileCount = 0
        var firstVolatileAt: Duration?
        var lastFinalAt: Duration?

        let consumer = Task {
            for try await result in transcriber.results {
                let elapsed = clockStart.duration(to: .now)
                let text = String(result.text.characters)
                if result.isFinal {
                    finalCount += 1
                    lastFinalAt = elapsed
                    appendedFinalText += text
                    overwriteFinalText = text
                    print("[\(elapsed)] FINAL len=\(text.count) appended-total-len=\(appendedFinalText.count) overwrite-total-len=\(overwriteFinalText.count) text=\(text)")
                } else {
                    volatileCount += 1
                    if firstVolatileAt == nil { firstVolatileAt = elapsed }
                    print("[\(elapsed)] volatile len=\(text.count) text=\(text)")
                }
            }
        }

        // Feed buffers at the file's own real-time pace, in ~100ms chunks,
        // the way a live AVAudioEngine tap would deliver them.
        let framesPerChunk = AVAudioFrameCount(sourceFormat.sampleRate * 0.1)
        let buffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: framesPerChunk)!
        var totalFramesFed: AVAudioFramePosition = 0
        let feedStart = ContinuousClock.now

        while true {
            buffer.frameLength = 0
            do {
                try sourceFile.read(into: buffer, frameCount: framesPerChunk)
            } catch {
                // AVAudioFile.read can throw right at end-of-file instead of
                // returning frameLength 0; treat that the same as end-of-file.
                fputs("read-at-eof (treated as end-of-file)=\(error)\n", stderr)
                break
            }
            if buffer.frameLength == 0 { break }
            totalFramesFed += AVAudioFramePosition(buffer.frameLength)

            let outputBuffer = AVAudioPCMBuffer(
                pcmFormat: analyzerFormat,
                frameCapacity: AVAudioFrameCount(Double(buffer.frameLength) * (analyzerFormat.sampleRate / sourceFormat.sampleRate) + 16)
            )!
            var error: NSError?
            var suppliedThisChunk = false
            converter.convert(to: outputBuffer, error: &error) { _, status in
                // The converter may call this block more than once per convert() call
                // (e.g. to satisfy a resampling ratio); only the first call gets real
                // data, subsequent calls must report .noDataNow or the same buffer
                // gets fed again, corrupting the stream.
                if suppliedThisChunk {
                    status.pointee = .noDataNow
                    return nil
                }
                suppliedThisChunk = true
                status.pointee = .haveData
                return buffer
            }
            if let error {
                // A too-small trailing chunk can fail to satisfy the resampling ratio;
                // skip it rather than aborting the stream before finalization runs.
                fputs("chunk-convert-error (skipped)=\(error)\n", stderr)
                continue
            }
            inputBuilder.yield(AnalyzerInput(buffer: outputBuffer))

            let elapsedSourceTime = Duration.seconds(Double(totalFramesFed) / sourceFormat.sampleRate)
            let elapsedWallTime = feedStart.duration(to: .now)
            if elapsedSourceTime > elapsedWallTime {
                try await Task.sleep(for: elapsedSourceTime - elapsedWallTime)
            }
        }

        print("finished-feeding audio-seconds=\(Double(totalFramesFed) / sourceFormat.sampleRate)")
        inputBuilder.finish()
        try await analyzer.finalizeAndFinishThroughEndOfInput()
        try await consumer.value

        let totalElapsed = clockStart.duration(to: .now)
        print("--- summary ---")
        print("final-results-count=\(finalCount)")
        print("volatile-results-count=\(volatileCount)")
        print("first-volatile-at=\(firstVolatileAt.map(String.init(describing:)) ?? "n/a")")
        print("last-final-at=\(lastFinalAt.map(String.init(describing:)) ?? "n/a")")
        print("total-elapsed=\(totalElapsed)")
        print("appended-final-text-length=\(appendedFinalText.count)")
        print("overwrite-final-text-length (last final only)=\(overwriteFinalText.count)")
        print("appended-final-text=\(appendedFinalText)")
        print("peak-resident-memory-bytes=\(peakResidentMemoryBytes())")
    }

    static func peakResidentMemoryBytes() -> UInt64 {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        return UInt64(usage.ru_maxrss)
    }
}
