import AVFAudio
import Foundation
import Speech

@available(macOS 26, *)
enum AppleSpeechTranscriptionError: LocalizedError, Equatable {
    case assetsNotInstalled
    case noSpeechDetected
    case cancelled
    case transcriptionFailed(String)

    var errorDescription: String? {
        switch self {
        case .assetsNotInstalled:
            return "Deutsche Sprachassets für die Gerätetranskription sind nicht installiert."
        case .noSpeechDetected:
            return "Apple Gerätetranskription hat keinen Text erkannt."
        case .cancelled:
            return "Transkription wurde abgebrochen."
        case .transcriptionFailed(let message):
            return "Apple Gerätetranskription ist fehlgeschlagen: \(message)"
        }
    }
}

/// Kapselt `DictationTranscriber` als lokalen, geräteinternen Drop-in für
/// `SpokenWorkflowPipeline.Transcriber`. Kein Routing, kein Fallback-Entscheid —
/// das übernimmt der Resolver aus einem Folge-Ticket (Wayfinder #98/#100).
@available(macOS 26, *)
enum AppleSpeechTranscriptionService {
    static let locale = Locale(identifier: "de-DE")
    static let minimumOSVersion = OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0)

    static var isAvailable: Bool {
        get async {
            let transcriber = DictationTranscriber(locale: locale, preset: .progressiveLongDictation)
            let status = await AssetInventory.status(forModules: [transcriber])
            return isAvailable(
                osSupportsAppleSpeech: ProcessInfo.processInfo.isOperatingSystemAtLeast(minimumOSVersion),
                assetStatus: status
            )
        }
    }

    /// Reine Entscheidungslogik, getrennt von den Speech-APIs, damit sie ohne
    /// installierte Sprachassets oder eine macOS-26-Maschine testbar bleibt.
    static func isAvailable(osSupportsAppleSpeech: Bool, assetStatus: AssetInventory.Status) -> Bool {
        osSupportsAppleSpeech && assetStatus == .installed
    }

    /// Transkribiert eine Audiodatei lokal auf dem Gerät. `customTerms` und
    /// `language` bleiben Teil der Signatur für Drop-in-Kompatibilität mit
    /// `SpokenWorkflowPipeline.Transcriber`, werden aber wie beim lokalen
    /// WhisperKit-Pfad nicht ausgewertet — die Locale ist fest auf de-DE gesetzt.
    static func transcribe(
        audioURL: URL,
        duration: TimeInterval,
        customTerms: [String],
        language: String,
        partialTranscriptHandler: ((String) -> Void)? = nil
    ) async throws -> String {
        let transcriber = DictationTranscriber(locale: locale, preset: .progressiveLongDictation)
        let status = await AssetInventory.status(forModules: [transcriber])
        guard status == .installed else {
            throw AppleSpeechTranscriptionError.assetsNotInstalled
        }

        do {
            let audioFile = try AVAudioFile(forReading: audioURL)
            let analyzer = try await SpeechAnalyzer(inputAudioFile: audioFile, modules: [transcriber])

            let collectingTask = Task {
                var finalText = ""
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    if result.isFinal {
                        // Each final result already carries the running transcript, not
                        // just its own segment, so overwriting (not appending) is correct —
                        // matches the validated behaviour in AppleSpeechProbe.swift (Wayfinder #101/#104).
                        finalText = text
                    } else {
                        partialTranscriptHandler?(text)
                    }
                }
                return finalText
            }

            try await analyzer.start(inputAudioFile: audioFile, finishAfterFile: true)
            let text = try await collectingTask.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                throw AppleSpeechTranscriptionError.noSpeechDetected
            }
            return text
        } catch is CancellationError {
            throw AppleSpeechTranscriptionError.cancelled
        } catch let error as AppleSpeechTranscriptionError {
            throw error
        } catch {
            throw AppleSpeechTranscriptionError.transcriptionFailed(error.localizedDescription)
        }
    }

    /// Baut eine Transkriptions-Closure, die direkt als `SpokenWorkflowPipeline.Transcriber`
    /// eingesetzt werden kann; `partialTranscriptHandler` erhält Teiltranskripte während des Laufs.
    static func makeTranscriber(
        partialTranscriptHandler: ((String) -> Void)? = nil
    ) -> SpokenWorkflowPipeline.Transcriber {
        { audioURL, duration, customTerms, language in
            try await transcribe(
                audioURL: audioURL,
                duration: duration,
                customTerms: customTerms,
                language: language,
                partialTranscriptHandler: partialTranscriptHandler
            )
        }
    }
}
