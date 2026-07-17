// PROTOTYPE — measurement harness for Wayfinder ticket #101, not production code.

import AVFAudio
import Foundation
import Speech

@main
struct AppleSpeechProbe {
    static func main() async {
        guard CommandLine.arguments.count == 2 else {
            fputs("Usage: AppleSpeechProbe <audio-file>\n", stderr)
            exit(64)
        }

        let locale = Locale(identifier: "de-DE")
        let transcriber = DictationTranscriber(locale: locale, preset: .longDictation)
        let status = await AssetInventory.status(forModules: [transcriber])
        print("asset-status=\(status)")
        print("installed-locales=\(await DictationTranscriber.installedLocales.map(\.identifier).joined(separator: ","))")

        guard status == .installed else {
            fputs("German dictation assets are not installed; do not download them during the offline run.\n", stderr)
            exit(69)
        }

        do {
            let audioFile = try AVAudioFile(forReading: URL(fileURLWithPath: CommandLine.arguments[1]))
            let transcriber = DictationTranscriber(locale: locale, preset: .longDictation)
            let analyzer = try await SpeechAnalyzer(inputAudioFile: audioFile, modules: [transcriber])
            let started = ContinuousClock.now
            let results = Task {
                var finalText = ""
                for try await result in transcriber.results where result.isFinal {
                    finalText = String(result.text.characters)
                }
                return finalText
            }

            try await analyzer.start(inputAudioFile: audioFile, finishAfterFile: true)
            let text = try await results.value
            let elapsed = started.duration(to: .now)
            print("final-text=\(text)")
            print("elapsed=\(elapsed)")
        } catch {
            fputs("probe-error=\(error.localizedDescription)\n", stderr)
            exit(70)
        }
    }
}
