import Foundation

private struct OpenAIErrorResponse: Decodable {
    struct APIError: Decodable {
        let message: String?
    }
    let error: APIError?
}

enum OpenAITranscriptionService {
    private static let model = "gpt-4o-mini-transcribe"
    private static let transcriptionsURL = URL(string: "https://api.openai.com/v1/audio/transcriptions")!

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 60
        return URLSession(configuration: configuration)
    }()

    static func transcribe(
        audioURL: URL,
        customTerms: [String] = [],
        language: String? = nil
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
                model: model,
                responseFormat: "text",
                prompt: prompt,
                language: trimmedLanguage?.isEmpty == true ? nil : trimmedLanguage
            )

            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw TranscriptionError.networkError("Ungültige Antwort")
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
        (try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data))?.error?.message
    }
}
