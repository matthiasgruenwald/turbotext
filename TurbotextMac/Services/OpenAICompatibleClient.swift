import Foundation

/// Shared request/response plumbing for OpenAI-compatible chat completion APIs
/// (OpenAI itself, Groq, and any future provider using the same wire format).
///
/// Callers stay responsible for their own error types/messages: this client
/// reports failures via `OpenAICompatibleError`, which each call site maps to
/// its own `LocalizedError` (e.g. `LLMError`, `GroqLLMError`).
enum OpenAICompatibleError: Error {
    case networkError(String)
    case apiError(String)
    case noContent
}

struct OpenAICompatibleClient {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    private struct ChatRequest: Encodable {
        let model: String
        let messages: [Message]
        let temperature: Double
    }

    private struct ChatResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                let content: String?
            }

            let message: Message?
        }

        let choices: [Choice]?
    }

    private struct ErrorResponse: Decodable {
        struct APIError: Decodable {
            let message: String?
        }

        let error: APIError?
    }

    let chatCompletionsURL: URL

    let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 45
        configuration.timeoutIntervalForResource = 45
        return URLSession(configuration: configuration)
    }()

    func complete(
        apiKey: String,
        model: String,
        messages: [Message],
        temperature: Double
    ) async throws -> String {
        let payload = ChatRequest(model: model, messages: messages, temperature: temperature)

        var request = URLRequest(url: chatCompletionsURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 45
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAICompatibleError.networkError("Keine gültige Antwort")
        }

        guard httpResponse.statusCode == 200 else {
            throw OpenAICompatibleError.apiError(errorMessage(from: data) ?? "Status \(httpResponse.statusCode)")
        }

        let result = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let content = result.choices?.first?.message?.content,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OpenAICompatibleError.noContent
        }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func errorMessage(from data: Data) -> String? {
        (try? JSONDecoder().decode(ErrorResponse.self, from: data))?.error?.message
    }
}
