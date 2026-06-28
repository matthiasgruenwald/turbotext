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

/// Outcome of a transcription request, capturing whether the Groq-to-OpenAI
/// fallback was triggered as part of this call.
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

private struct TranscriptionOpenAIErrorResponse: Decodable {
    struct APIError: Decodable {
        let message: String?
    }
    let error: APIError?
}

enum TranscriptionService {
    private static let remoteModel = "gpt-4o-mini-transcribe"
    private static let transcriptionsURL = URL(string: "https://api.openai.com/v1/audio/transcriptions")!

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 60
        return URLSession(configuration: configuration)
    }()

    /// Seam for tests: replace with a fake to avoid real Groq network calls.
    static var groqTranscribe: (URL, String, [String], String?) async throws -> (text: String, rateLimitInfo: GroqRateLimitInfo) = {
        audioURL, apiKey, customTerms, language in
        try await GroqTranscriptionService.transcribe(
            audioURL: audioURL,
            apiKey: apiKey,
            customTerms: customTerms,
            language: language
        )
    }

    /// Seam for tests: replace with a fake to avoid real OpenAI network calls.
    static var openAITranscribe: (URL, [String], String?) async throws -> String = {
        audioURL, customTerms, language in
        try await defaultOpenAITranscribe(audioURL: audioURL, customTerms: customTerms, language: language)
    }

    static func transcribe(
        audioURL: URL,
        durationSeconds: TimeInterval,
        customTerms: [String] = [],
        language: String? = nil
    ) async throws -> TranscriptionOutcome {
        let groqKey = KeychainService.load(key: .groqAPIKey)
        let fallbackWasActive = await MainActor.run { GroqQuotaStore.shared.fallbackActive }

        if let groqKey, !fallbackWasActive {
            do {
                let (text, info) = try await groqTranscribe(audioURL, groqKey, customTerms, language)
                await MainActor.run {
                    if let remaining = info.remainingAudioSeconds {
                        GroqQuotaStore.shared.update(remainingSeconds: remaining, resetAt: info.resetAt)
                    }
                    GroqQuotaStore.shared.recordUsage(seconds: Int(durationSeconds.rounded()))
                }
                return .success(text)
            } catch GroqTranscriptionError.rateLimitExceeded(let resetAt) {
                await MainActor.run { GroqQuotaStore.shared.activateFallback(resetAt: resetAt) }
                let text = try await openAITranscribe(audioURL, customTerms, language)
                return .fallbackActivated(text)
            }
            // other Groq errors propagate as-is
        }

        let text = try await openAITranscribe(audioURL, customTerms, language)
        return fallbackWasActive ? .fallbackActivated(text) : .success(text)
    }

    /// Proactive quota check, mirroring the network call made by `transcribe()`.
    /// `TranscriptionService` is the sole writer of `GroqQuotaStore` state.
    static func checkGroqQuotaIfNeeded(apiKey: String) async {
        do {
            let info = try await GroqTranscriptionService.checkQuota(apiKey: apiKey)
            if let remaining = info.remainingAudioSeconds {
                await MainActor.run { GroqQuotaStore.shared.update(remainingSeconds: remaining, resetAt: info.resetAt) }
            }
        } catch GroqTranscriptionError.rateLimitExceeded(let resetAt) {
            await MainActor.run { GroqQuotaStore.shared.activateFallback(resetAt: resetAt) }
        } catch {
            // Best-effort check; a real transcription will fill the quota later.
        }
    }

    private static func defaultOpenAITranscribe(
        audioURL: URL,
        customTerms: [String],
        language: String?
    ) async throws -> String {
        guard let apiKey = KeychainService.load(key: .openAIAPIKey) else {
            throw TranscriptionError.notConfigured
        }

        return try await Task.detached(priority: .userInitiated) {
            defer {
                try? FileManager.default.removeItem(at: audioURL)
            }

            let boundary = UUID().uuidString
            var request = URLRequest(url: transcriptionsURL)
            request.httpMethod = "POST"
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            request.setValue("text/plain, application/json", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 60
            request.cachePolicy = .reloadIgnoringLocalCacheData

            let audioData = try Data(contentsOf: audioURL, options: [.mappedIfSafe])

            let prompt = customTerms.isEmpty
                ? nil
                : "Eigennamen und Begriffe: \(customTerms.joined(separator: ", "))"
            let trimmedLanguage = language?.trimmingCharacters(in: .whitespacesAndNewlines)

            request.httpBody = MultipartFormDataBuilder.build(
                boundary: boundary,
                audioData: audioData,
                filename: "audio.m4a",
                mimeType: "audio/m4a",
                model: remoteModel,
                responseFormat: "text",
                prompt: prompt,
                language: trimmedLanguage?.isEmpty == true ? nil : trimmedLanguage
            )

            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw TranscriptionError.networkError("Ungueltige Antwort")
            }

            guard httpResponse.statusCode == 200 else {
                throw TranscriptionError.apiError(openAIErrorMessage(from: data) ?? "Status \(httpResponse.statusCode)")
            }

            guard let text = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else {
                throw TranscriptionError.apiError("Transkription fehlgeschlagen")
            }

            return text
        }.value
    }

    private static func openAIErrorMessage(from data: Data) -> String? {
        (try? JSONDecoder().decode(TranscriptionOpenAIErrorResponse.self, from: data))?.error?.message
    }
}
