import Foundation

enum TranscriptionError: LocalizedError {
    case noFile
    case notConfigured
    case networkError(String)
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .noFile:
            return "Keine Audio-Datei gefunden"
        case .notConfigured:
            return "API Key fehlt. Bitte in den Einstellungen hinterlegen."
        case .networkError(let msg):
            return "Netzwerkfehler: \(msg)"
        case .apiError(let msg):
            return "API-Fehler: \(msg)"
        }
    }
}

enum TranscriptionOutcome {
    case success(String)
    case fallbackActivated(String)

    var text: String {
        switch self {
        case .success(let text), .fallbackActivated(let text):
            return text
        }
    }
}

enum TranscriptionService {
    private static let router = CloudTranscriptionRouter()

    static func transcribe(
        audioURL: URL,
        durationSeconds: TimeInterval,
        customTerms: [String] = [],
        language: String? = nil
    ) async throws -> TranscriptionOutcome {
        try await router.transcribe(
            audioURL: audioURL,
            durationSeconds: durationSeconds,
            customTerms: customTerms,
            language: language
        )
    }
}
