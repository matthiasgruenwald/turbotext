import Foundation

enum GroqLLMError: LocalizedError {
    case notConfigured
    case networkError(String)
    case apiError(String)
    case noContent

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Groq API Key fehlt."
        case .networkError(let msg):
            return "Verbindungsproblem: \(msg)"
        case .apiError(let msg):
            return "Fehler von Groq: \(msg)"
        case .noContent:
            return "Keine Antwort erhalten. Bitte nochmal versuchen."
        }
    }
}

enum GroqLLMService {
    private static let model = "openai/gpt-oss-120b"
    private static let client = OpenAICompatibleClient(
        chatCompletionsURL: URL(string: "https://api.groq.com/openai/v1/chat/completions")!
    )

    static func complete(
        text: String,
        systemPrompt: String,
        temperature: Double
    ) async throws -> String {
        guard let apiKey = KeychainService.load(key: .groqAPIKey) else {
            throw GroqLLMError.notConfigured
        }

        do {
            return try await client.complete(
                apiKey: apiKey,
                model: model,
                messages: [
                    .init(role: "system", content: systemPrompt),
                    .init(role: "user", content: text),
                ],
                temperature: temperature
            )
        } catch OpenAICompatibleError.networkError(let msg) {
            throw GroqLLMError.networkError(msg)
        } catch OpenAICompatibleError.apiError(let msg) {
            throw GroqLLMError.apiError(msg)
        } catch OpenAICompatibleError.noContent {
            throw GroqLLMError.noContent
        }
    }
}
