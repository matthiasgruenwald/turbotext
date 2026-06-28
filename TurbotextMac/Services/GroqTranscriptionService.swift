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

            let prompt = customTerms.isEmpty
                ? nil
                : "Eigennamen und Begriffe: \(customTerms.joined(separator: ", "))"
            let trimmedLanguage = language?.trimmingCharacters(in: .whitespacesAndNewlines)

            request.httpBody = MultipartFormDataBuilder.build(
                boundary: boundary,
                audioData: audioData,
                filename: "audio.m4a",
                mimeType: "audio/m4a",
                model: model,
                responseFormat: "text",
                prompt: prompt,
                language: trimmedLanguage?.isEmpty == true ? nil : trimmedLanguage
            )

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

    /// Lightweight proactive quota check: posts a near-silent clip to fill in
    /// `x-ratelimit-remaining-audio-seconds` before any real transcription happens.
    static func checkQuota(apiKey: String) async throws -> GroqRateLimitInfo {
        return try await Task.detached(priority: .utility) {
            let boundary = UUID().uuidString
            var request = URLRequest(url: transcriptionsURL)
            request.httpMethod = "POST"
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 15
            request.cachePolicy = .reloadIgnoringLocalCacheData

            var body = Data()
            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"file\"; filename=\"quota-check.wav\"\r\n")
            body.append("Content-Type: audio/wav\r\n\r\n")
            body.append(silentWavData)
            body.append("\r\n")

            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n")
            body.append(model)
            body.append("\r\n")

            body.append("--\(boundary)--\r\n")
            request.httpBody = body

            let (_, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw GroqTranscriptionError.networkError("Ungueltige Antwort")
            }

            if httpResponse.statusCode == 429 {
                throw GroqTranscriptionError.rateLimitExceeded(resetAt: parseResetDate(from: httpResponse))
            }

            return GroqRateLimitInfo(
                remainingAudioSeconds: parseRemainingSeconds(from: httpResponse),
                resetAt: parseResetDate(from: httpResponse)
            )
        }.value
    }

    /// 100ms of silence at 16kHz mono — minimal real audio so Groq returns
    /// rate-limit headers without meaningfully spending the user's quota.
    private static let silentWavData: Data = makeSilentWav(durationSeconds: 0.1, sampleRate: 16000)

    private static func makeSilentWav(durationSeconds: Double, sampleRate: Int) -> Data {
        let bytesPerSample = 2
        let numSamples = Int(durationSeconds * Double(sampleRate))
        let dataSize = numSamples * bytesPerSample

        func littleEndian(_ value: UInt32) -> Data {
            var v = value.littleEndian
            return Data(bytes: &v, count: 4)
        }
        func littleEndian(_ value: UInt16) -> Data {
            var v = value.littleEndian
            return Data(bytes: &v, count: 2)
        }

        var wav = Data()
        wav.append("RIFF")
        wav.append(littleEndian(UInt32(36 + dataSize)))
        wav.append("WAVE")
        wav.append("fmt ")
        wav.append(littleEndian(UInt32(16)))
        wav.append(littleEndian(UInt16(1))) // PCM
        wav.append(littleEndian(UInt16(1))) // mono
        wav.append(littleEndian(UInt32(sampleRate)))
        wav.append(littleEndian(UInt32(sampleRate * bytesPerSample)))
        wav.append(littleEndian(UInt16(bytesPerSample)))
        wav.append(littleEndian(UInt16(16))) // bits per sample
        wav.append("data")
        wav.append(littleEndian(UInt32(dataSize)))
        wav.append(Data(count: dataSize))
        return wav
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
