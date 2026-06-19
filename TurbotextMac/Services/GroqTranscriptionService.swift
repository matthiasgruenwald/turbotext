import Foundation

enum GroqTranscriptionError: LocalizedError {
    case notConfigured
    case rateLimitExceeded(resetAt: Date?)
    case networkError(String)
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Groq API Key fehlt."
        case .rateLimitExceeded:
            return "Groq-Kontingent aufgebraucht. Wechsel zu OpenAI."
        case .networkError(let msg):
            return "Netzwerkfehler: \(msg)"
        case .apiError(let msg):
            return "Groq-Fehler: \(msg)"
        }
    }
}

struct GroqRateLimitInfo {
    let remainingAudioSeconds: Int?
    let resetAt: Date?
}

private struct GroqErrorResponse: Decodable {
    struct APIError: Decodable {
        let message: String?
    }
    let error: APIError?
}

enum GroqTranscriptionService {
    private static let model = "whisper-large-v3-turbo"
    private static let transcriptionsURL = URL(string: "https://api.groq.com/openai/v1/audio/transcriptions")!

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.waitsForConnectivity = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 60
        return URLSession(configuration: config)
    }()

    static func transcribe(
        audioURL: URL,
        apiKey: String,
        customTerms: [String] = [],
        language: String? = nil
    ) async throws -> (text: String, rateLimitInfo: GroqRateLimitInfo) {
        return try await Task.detached(priority: .userInitiated) {
            let boundary = UUID().uuidString
            var request = URLRequest(url: transcriptionsURL)
            request.httpMethod = "POST"
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            request.setValue("text/plain, application/json", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 60
            request.cachePolicy = .reloadIgnoringLocalCacheData

            let audioData = try Data(contentsOf: audioURL, options: [.mappedIfSafe])

            var body = Data()
            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.m4a\"\r\n")
            body.append("Content-Type: audio/m4a\r\n\r\n")
            body.append(audioData)
            body.append("\r\n")

            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n")
            body.append(model)
            body.append("\r\n")

            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n")
            body.append("text")
            body.append("\r\n")

            if !customTerms.isEmpty {
                let prompt = "Eigennamen und Begriffe: \(customTerms.joined(separator: ", "))"
                body.append("--\(boundary)\r\n")
                body.append("Content-Disposition: form-data; name=\"prompt\"\r\n\r\n")
                body.append(prompt)
                body.append("\r\n")
            }

            if let language, !language.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                body.append("--\(boundary)\r\n")
                body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n")
                body.append(language.trimmingCharacters(in: .whitespacesAndNewlines))
                body.append("\r\n")
            }

            body.append("--\(boundary)--\r\n")
            request.httpBody = body

            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw GroqTranscriptionError.networkError("Ungueltige Antwort")
            }

            if httpResponse.statusCode == 429 {
                let resetAt = parseResetDate(from: httpResponse)
                throw GroqTranscriptionError.rateLimitExceeded(resetAt: resetAt)
            }

            guard httpResponse.statusCode == 200 else {
                let msg = groqErrorMessage(from: data) ?? "Status \(httpResponse.statusCode)"
                throw GroqTranscriptionError.apiError(msg)
            }

            guard let text = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else {
                throw GroqTranscriptionError.apiError("Transkription fehlgeschlagen")
            }

            let rateLimitInfo = GroqRateLimitInfo(
                remainingAudioSeconds: parseRemainingSeconds(from: httpResponse),
                resetAt: parseResetDate(from: httpResponse)
            )

            return (text, rateLimitInfo)
        }.value
    }

    private static func groqErrorMessage(from data: Data) -> String? {
        (try? JSONDecoder().decode(GroqErrorResponse.self, from: data))?.error?.message
    }

    private static func parseRemainingSeconds(from response: HTTPURLResponse) -> Int? {
        guard let value = response.value(forHTTPHeaderField: "x-ratelimit-remaining-audio-seconds") else {
            return nil
        }
        return Int(value)
    }

    private static func parseResetDate(from response: HTTPURLResponse) -> Date? {
        guard let value = response.value(forHTTPHeaderField: "x-ratelimit-reset-audio") else {
            return nil
        }
        if let seconds = TimeInterval(value) {
            return Date().addingTimeInterval(seconds)
        }
        // fallback: 24h from now if header is present but unparseable
        return Date().addingTimeInterval(86400)
    }
}

private extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
