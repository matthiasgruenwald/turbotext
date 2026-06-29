import Foundation

enum LLMError: LocalizedError {
    case notConfigured
    case networkError(String)
    case apiError(String)
    case noContent

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "OpenAI API Key fehlt. Bitte in den Einstellungen hinterlegen."
        case .networkError(let msg):
            return "Verbindungsproblem: \(msg)"
        case .apiError(let msg):
            return "Fehler von OpenAI: \(msg)"
        case .noContent:
            return "Keine Antwort erhalten. Bitte nochmal versuchen."
        }
    }
}

enum RewriteModel: String {
    case fastEdit = "gpt-4o-mini"
    case rageMode = "gpt-4o"
}

enum RewriteProviderMode: String, Codable, Equatable {
    case auto
    case immerOpenAI
}

enum LLMService {
    private static let client = OpenAICompatibleClient(
        chatCompletionsURL: URL(string: "https://api.openai.com/v1/chat/completions")!
    )

    /// Seam for tests/providers: replace with a fake or a different provider (e.g. Groq)
    /// to avoid real OpenAI network calls or to route the chat completion elsewhere.
    static var providerComplete: (String, String, RewriteModel, Double) async throws -> String = {
        text, systemPrompt, model, temperature in
        try await defaultOpenAIComplete(
            text: text,
            systemPrompt: systemPrompt,
            model: model,
            temperature: temperature
        )
    }

    /// Seam for tests: replace to fake Groq instead of hitting the real network.
    static var groqComplete: (String, String, Double) async throws -> String = {
        text, systemPrompt, temperature in
        try await GroqLLMService.complete(text: text, systemPrompt: systemPrompt, temperature: temperature)
    }

    /// Where the provider mode (Auto / Immer OpenAI) comes from. Defaults to `.auto`;
    /// the settings UI injects the real value (`AppSettings.rewritingProviderMode`) at app launch.
    static var providerMode: () -> RewriteProviderMode = { .auto }

    /// Whether a Groq API key is configured. Seam so tests don't depend on Keychain state.
    static var hasGroqKey: () -> Bool = {
        KeychainService.load(key: .groqAPIKey) != nil
    }

    static func improve(
        text: String,
        settings: TextImprovementSettings,
        model: RewriteModel = .fastEdit
    ) async throws -> String {
        try await complete(
            text: text,
            systemPrompt: buildSystemPrompt(settings: settings),
            model: model,
            temperature: 0.3
        )
    }

    static func dampfAblassen(
        text: String,
        systemPrompt: String,
        model: RewriteModel = .rageMode
    ) async throws -> String {
        try await complete(
            text: text,
            systemPrompt: systemPrompt,
            model: model,
            temperature: 0.4
        )
    }

    static func addEmojis(
        text: String,
        settings: EmojiTextSettings,
        model: RewriteModel = .fastEdit
    ) async throws -> String {
        try await complete(
            text: text,
            systemPrompt: buildEmojiSystemPrompt(density: settings.emojiDensity),
            model: model,
            temperature: 0.3
        )
    }

    private static func complete(
        text: String,
        systemPrompt: String,
        model: RewriteModel,
        temperature: Double
    ) async throws -> String {
        guard providerMode() == .auto, hasGroqKey() else {
            return try await providerComplete(text, systemPrompt, model, temperature)
        }

        do {
            return try await groqComplete(text, systemPrompt, temperature)
        } catch {
            return try await providerComplete(text, systemPrompt, model, temperature)
        }
    }

    private static func defaultOpenAIComplete(
        text: String,
        systemPrompt: String,
        model: RewriteModel,
        temperature: Double
    ) async throws -> String {
        guard let apiKey = KeychainService.load(key: .openAIAPIKey) else {
            throw LLMError.notConfigured
        }

        do {
            return try await client.complete(
                apiKey: apiKey,
                model: model.rawValue,
                messages: [
                    .init(role: "system", content: systemPrompt),
                    .init(role: "user", content: text),
                ],
                temperature: temperature
            )
        } catch OpenAICompatibleError.networkError(let msg) {
            throw LLMError.networkError(msg)
        } catch OpenAICompatibleError.apiError(let msg) {
            throw LLMError.apiError(msg)
        } catch OpenAICompatibleError.noContent {
            throw LLMError.noContent
        }
    }

    private static func buildEmojiSystemPrompt(density: EmojiTextSettings.EmojiDensity) -> String {
        let densityInstruction: String
        switch density {
        case .wenig:
            densityInstruction = "Setze nur vereinzelt Emojis ein, maximal 1-2 pro Absatz."
        case .mittel:
            densityInstruction = "Setze regelmaessig passende Emojis ein, etwa alle 1-2 Saetze."
        case .viel:
            densityInstruction = "Setze grosszuegig Emojis ein, gerne mehrere pro Satz."
        }

        return "Du erhaeltst ein gesprochenes Transkript. Gib den Text moeglichst originalgetreu zurueck, aber fuege passende Emojis ein. \(densityInstruction) Korrigiere offensichtliche Sprach- und Grammatikfehler. Behalte den Stil und die Bedeutung bei. Gib NUR den Text mit Emojis zurueck, keine Erklaerungen."
    }

    private static func buildSystemPrompt(settings: TextImprovementSettings) -> String {
        if !settings.systemPrompt.isEmpty {
            var prompt = settings.systemPrompt
            if !settings.customTerms.isEmpty {
                prompt += "\n\nWichtig: Diese Eigennamen und Fachbegriffe muessen exakt so geschrieben werden: \(settings.customTerms.joined(separator: ", "))"
            }
            if !settings.context.isEmpty {
                prompt += "\n\nKontext: \(settings.context)"
            }
            return prompt
        }

        var prompt = """
        Du bist ein Lektor und Schreibassistent. Verbessere den folgenden Text:
        - Korrigiere Rechtschreibung und Grammatik
        - Verbessere die Formulierung und den Lesefluss
        - Behalte die urspruengliche Bedeutung bei
        - Gib NUR den verbesserten Text zurueck, keine Erklaerungen
        """

        switch settings.tone {
        case .formal:
            prompt += "\n- Verwende einen formellen, professionellen Ton"
        case .neutral:
            prompt += "\n- Verwende einen neutralen, klaren Ton"
        case .casual:
            prompt += "\n- Verwende einen lockeren, natuerlichen Ton"
        }

        if !settings.customTerms.isEmpty {
            prompt += "\n\nWichtig: Diese Eigennamen und Fachbegriffe muessen exakt so geschrieben werden: \(settings.customTerms.joined(separator: ", "))"
        }

        if !settings.context.isEmpty {
            prompt += "\n\nKontext: \(settings.context)"
        }

        return prompt
    }
}
