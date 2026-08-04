import AVFAudio
import Foundation
import OSLog
import Speech

private let appleSpeechLogger = Logger(subsystem: "app.turbotext.mac", category: "Transcription")
private let assetReservationLogger = Logger(subsystem: "app.turbotext.mac", category: "LiveDictation")

enum AppleSpeechAvailabilityStatus: Equatable {
    case available
    case unsupportedOS
    case assetsNotInstalled
    case assetsDownloading
    case germanAssetsUnsupported

    var isAvailable: Bool { self == .available }

    /// Sprachasset-Sicherstellung (#178): Bei `.assetsNotInstalled` kann Turbotext die
    /// Installation anstoßen, bei `.assetsDownloading` läuft sie bereits — im Gegensatz
    /// zu den unsupported-Zuständen, in denen kein installierbares de-Asset existiert.
    var isAssetInstallationPossible: Bool {
        switch self {
        case .assetsNotInstalled, .assetsDownloading: return true
        case .available, .unsupportedOS, .germanAssetsUnsupported: return false
        }
    }
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

/// Bounds the Apple-Gerätetranskription so a stalled engine (assets broken,
/// audio consumed but zero results — #177) can never hang a workflow forever.
/// Ungated so the race logic stays testable without the macOS-26 Speech APIs.
enum TranscriptionDeadline {
    struct Exceeded: Error, Equatable {}

    /// Healthy file decoding is faster than realtime, so the recording duration
    /// bounds a healthy run; the buffer covers engine startup overhead.
    static func deadline(for duration: TimeInterval) -> Duration {
        max(.seconds(20), .seconds(duration + 20))
    }

    // A task group would await its cancelled child until the stalled engine
    // unwinds — which it never does — so the loser is detached instead,
    // like `smoothedWithinBudget` (#163). Outer cancellation is wired through
    // `withTaskCancellationHandler` because unstructured tasks don't inherit it.
    static func run<T: Sendable>(
        within deadline: Duration,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let resolver = DeadlineResultResolver<T>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
                let work = Task {
                    do {
                        await resolver.resolve(.success(try await operation()))
                    } catch {
                        await resolver.resolve(.failure(error))
                    }
                }
                let timer = Task {
                    do {
                        try await Task.sleep(for: deadline)
                    } catch {
                        return
                    }
                    await resolver.expire()
                }
                Task {
                    await resolver.arm(continuation: continuation, work: work, timer: timer)
                }
            }
        } onCancel: {
            Task { await resolver.cancel() }
        }
    }
}

private actor DeadlineResultResolver<T> {
    private var continuation: CheckedContinuation<T, Error>?
    private var work: Task<Void, Never>?
    private var timer: Task<Void, Never>?
    private var pending: Result<T, Error>?
    private var finished = false

    func arm(continuation: CheckedContinuation<T, Error>, work: Task<Void, Never>, timer: Task<Void, Never>) {
        self.work = work
        self.timer = timer
        if let pending {
            continuation.resume(with: pending)
        } else {
            self.continuation = continuation
        }
    }

    func resolve(_ result: Result<T, Error>) {
        timer?.cancel()
        finish(result)
    }

    func expire() {
        work?.cancel()
        finish(.failure(TranscriptionDeadline.Exceeded()))
    }

    func cancel() {
        work?.cancel()
        timer?.cancel()
        finish(.failure(CancellationError()))
    }

    private func finish(_ result: Result<T, Error>) {
        guard !finished else { return }
        finished = true
        if let continuation {
            self.continuation = nil
            continuation.resume(with: result)
        } else {
            pending = result
        }
    }
}

@available(macOS 26, *)
enum AppleSpeechTranscriptionError: LocalizedError, Equatable {
    case assetsNotInstalled
    case noSpeechDetected
    case cancelled
    case timedOut
    case transcriptionFailed(String)

    var errorDescription: String? {
        switch self {
        case .assetsNotInstalled:
            return AppleSpeechUnavailableHint.assetsLoadingMessage
        case .noSpeechDetected:
            return "Apple Gerätetranskription hat keinen Text erkannt."
        case .cancelled:
            return "Transkription wurde abgebrochen."
        case .timedOut:
            return "Apple Gerätetranskription hat nicht rechtzeitig geantwortet – bitte erneut versuchen."
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

    /// `frequentFinalization` begrenzt das volatile Fenster: ohne die Option bleibt
    /// dessen Startzeit stehen und der Analyzer dekodiert wachsende Audiobereiche
    /// neu, bis der Speech-Dienst mit `SFSpeechErrorCodeInternalServiceError`
    /// aussteigt (#155). Nur der Live-Pfad braucht das — dateibasiert wird ohnehin
    /// am Stück finalisiert.
    static func makeDictationTranscriber(frequentFinalization: Bool = false) -> DictationTranscriber {
        let preset = DictationTranscriber.Preset.progressiveLongDictation
        guard frequentFinalization else {
            return DictationTranscriber(locale: locale, preset: preset)
        }
        return DictationTranscriber(
            locale: locale,
            contentHints: preset.contentHints,
            transcriptionOptions: preset.transcriptionOptions,
            reportingOptions: preset.reportingOptions.union([.frequentFinalization]),
            attributeOptions: preset.attributeOptions
        )
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

    /// Sprachasset-Sicherstellung (#178): Ohne Reservierung meldet die API für das
    /// Cryptex-Modell `.supported`, obwohl die Datei auf Disk liegt, und der Zustand
    /// flackert. Die Reservierung hebt ihn auf `.installed` und hält ihn dort; sie ist
    /// an die laufende App gebunden und muss pro Start erneut erfolgen. Wirft nie —
    /// ein Fehlschlag darf den App-Start nicht beenden.
    static func reserveAssets() async {
        do {
            let result = try await AssetInventory.reserve(locale: locale)
            assetReservationLogger.info("de-DE asset reservation succeeded (result=\(result))")
        } catch {
            assetReservationLogger.error(
                "de-DE asset reservation failed: \(error.localizedDescription, privacy: .public)"
            )
        }
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

        let cap = TranscriptionDeadline.deadline(for: duration)
        do {
            return try await TranscriptionDeadline.run(within: cap) {
                try await decode(
                    audioURL: audioURL,
                    transcriber: transcriber,
                    partialTranscriptHandler: partialTranscriptHandler
                )
            }
        } catch is TranscriptionDeadline.Exceeded {
            appleSpeechLogger.error(
                "transcription deadline exceeded cap=\(cap.components.seconds)s recording=\(String(format: "%.1f", duration), privacy: .public)s"
            )
            throw AppleSpeechTranscriptionError.timedOut
        } catch is CancellationError {
            throw AppleSpeechTranscriptionError.cancelled
        } catch let error as AppleSpeechTranscriptionError {
            throw error
        } catch {
            throw AppleSpeechTranscriptionError.transcriptionFailed(error.localizedDescription)
        }
    }

    private static func decode(
        audioURL: URL,
        transcriber: DictationTranscriber,
        partialTranscriptHandler: ((String) -> Void)?
    ) async throws -> String {
        let audioFile = try AVAudioFile(forReading: audioURL)
        let analyzer = SpeechAnalyzer(modules: [transcriber])

        async let collected = collectResults(
            of: transcriber,
            partialTranscriptHandler: partialTranscriptHandler
        )

        try await analyzer.start(inputAudioFile: audioFile, finishAfterFile: true)
        let text = try await collected.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw AppleSpeechTranscriptionError.noSpeechDetected
        }
        return text
    }

    private static func collectResults(
        of transcriber: DictationTranscriber,
        partialTranscriptHandler: ((String) -> Void)?
    ) async throws -> String {
        var finalText = ""
        for try await result in transcriber.results {
            let text = String(result.text.characters)
            if result.isFinal {
                let separator = finalText.isEmpty ? "" : " "
                finalText += separator + text
            } else {
                partialTranscriptHandler?(finalText.isEmpty ? text : finalText + " " + text)
            }
        }
        return finalText
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
