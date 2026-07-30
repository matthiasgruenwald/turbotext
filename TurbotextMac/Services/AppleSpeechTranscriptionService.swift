import AVFAudio
import Foundation
import Speech

enum AppleSpeechAvailabilityStatus: Equatable {
    case available
    case unsupportedOS
    case assetsNotInstalled
    case assetsDownloading
    case germanAssetsUnsupported

    var isAvailable: Bool { self == .available }
}

enum AppleSpeechAssetInstallationError: LocalizedError, Equatable {
    case requestUnavailable
    case unsupportedOS

    var errorDescription: String? {
        switch self {
        case .requestUnavailable:
            return "Die Apple-Sprachassets können auf diesem Mac derzeit nicht zur Installation reserviert werden."
        case .unsupportedOS:
            return "Apple-Gerätetranskription erfordert macOS 26 oder neuer."
        }
    }
}

enum LocalTranscriptionUnavailableError: LocalizedError {
    case selectedBackendUnavailable

    var errorDescription: String? {
        "Die gewählte lokale Transkription ist nicht verfügbar."
    }
}

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

    static func makeDictationTranscriber() -> DictationTranscriber {
        DictationTranscriber(locale: locale, preset: .progressiveLongDictation)
    }

    static var isAvailable: Bool {
        get async {
            let transcriber = makeDictationTranscriber()
            let status = await AssetInventory.status(forModules: [transcriber])
            return availabilityStatus(
                osSupportsAppleSpeech: ProcessInfo.processInfo.isOperatingSystemAtLeast(minimumOSVersion),
                assetStatus: status
            ).isAvailable
        }
    }

    /// Reine Entscheidungslogik, getrennt von den Speech-APIs, damit sie ohne
    /// installierte Sprachassets oder eine macOS-26-Maschine testbar bleibt.
    static func isAvailable(osSupportsAppleSpeech: Bool, assetStatus: AssetInventory.Status) -> Bool {
        availabilityStatus(osSupportsAppleSpeech: osSupportsAppleSpeech, assetStatus: assetStatus).isAvailable
    }

    static func availabilityStatus(
        osSupportsAppleSpeech: Bool,
        assetStatus: AssetInventory.Status
    ) -> AppleSpeechAvailabilityStatus {
        guard osSupportsAppleSpeech else { return .unsupportedOS }

        switch assetStatus {
        case .installed: return .available
        case .supported: return .assetsNotInstalled
        case .downloading: return .assetsDownloading
        case .unsupported: return .germanAssetsUnsupported
        @unknown default: return .germanAssetsUnsupported
        }
    }

    static var availabilityStatus: AppleSpeechAvailabilityStatus {
        get async {
            let transcriber = makeDictationTranscriber()
            let assetStatus = await AssetInventory.status(forModules: [transcriber])
            return availabilityStatus(
                osSupportsAppleSpeech: ProcessInfo.processInfo.isOperatingSystemAtLeast(minimumOSVersion),
                assetStatus: assetStatus
            )
        }
    }

    static func installAssets() async throws -> AppleSpeechAvailabilityStatus {
        let transcriber = makeDictationTranscriber()
        guard let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) else {
            throw AppleSpeechAssetInstallationError.requestUnavailable
        }
        try await request.downloadAndInstall()
        return await availabilityStatus
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
        let transcriber = makeDictationTranscriber()
        let status = await AssetInventory.status(forModules: [transcriber])
        guard status == .installed else {
            throw AppleSpeechTranscriptionError.assetsNotInstalled
        }

        do {
            let audioFile = try AVAudioFile(forReading: audioURL)
            let analyzer = SpeechAnalyzer(modules: [transcriber])

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

    /// Erzeugt eine Live-Streaming-Session, die den Analyzer mit laufendem
    /// Mikrofonaudio speist. `sourceFormat` ist das Format des AudioRecorder-Taps.
    static func makeLiveSession(sourceFormat: AVAudioFormat) async throws -> LiveTranscriptionSession {
        let session = LiveTranscriptionSession()
        try await session.start(sourceFormat: sourceFormat)
        return session
    }

    /// Schließt eine Live-Session ab und liefert den Transkriptions-Text.
    /// Fällt auf den dateibasierten Pfad zurück, wenn der Streambetrieb
    /// fehlgeschlagen ist — die Datei wurde parallel mitgeschrieben.
    static func finishLiveSession(
        _ session: LiveTranscriptionSession,
        fallbackAudioURL: URL?,
        fallbackDuration: TimeInterval,
        customTerms: [String],
        language: String
    ) async throws -> String {
        session.finish()

        let deadline = Date().addingTimeInterval(10)
        while session.phase == .running && Date() < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }

        if case .finished = session.phase {
            let text = session.finalizeText()
            if !text.isEmpty { return text }
        }

        guard let fallbackAudioURL else {
            if case .failed(let message) = session.phase {
                throw AppleSpeechTranscriptionError.transcriptionFailed(message)
            }
            throw AppleSpeechTranscriptionError.noSpeechDetected
        }

        return try await transcribe(
            audioURL: fallbackAudioURL,
            duration: fallbackDuration,
            customTerms: customTerms,
            language: language
        )
    }
}
