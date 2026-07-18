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

/// A backend capable of completing a chat-style rewrite request.
protocol LLMProvider {
    /// Display name for the concrete model used, shown in the post-insert completion
    /// label (#128), e.g. "gpt-4o" or "openai/gpt-oss-120b".
    var modelName: String { get }
    func complete(text: String, systemPrompt: String, temperature: Double) async throws -> String
}

/// OpenAI-backed provider. Bound to a specific `RewriteModel` at construction time,
/// since different rewrite operations use different OpenAI models.
struct OpenAIProvider: LLMProvider {
    let model: RewriteModel
    var modelName: String { model.rawValue }
    private static let client = OpenAICompatibleClient(
        chatCompletionsURL: URL(string: "https://api.openai.com/v1/chat/completions")!
    )

    func complete(text: String, systemPrompt: String, temperature: Double) async throws -> String {
        guard let apiKey = KeychainService.load(key: .openAIAPIKey) else {
            throw LLMError.notConfigured
        }

        do {
            return try await Self.client.complete(
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
}

/// Groq-backed provider, used as the preferred backend in Auto mode.
struct GroqProvider: LLMProvider {
    var modelName: String { GroqLLMService.model }

    func complete(text: String, systemPrompt: String, temperature: Double) async throws -> String {
        try await GroqLLMService.complete(text: text, systemPrompt: systemPrompt, temperature: temperature)
    }
}

/// Implements the Auto-fallback routing: prefer Groq when mode is `.auto` and a Groq key
/// exists, fall back to OpenAI if Groq fails, otherwise always use OpenAI.
struct ProviderRouter {
    /// Which provider actually completed the request, for the #128 completion label.
    struct Outcome: Equatable {
        let text: String
        let provider: OnlineProvider
        let model: String
    }

    let providerMode: RewriteProviderMode
    let hasGroqKey: Bool

    func complete(
        text: String,
        systemPrompt: String,
        temperature: Double,
        openAIProvider: LLMProvider,
        groqProvider: LLMProvider
    ) async throws -> String {
        try await completeWithOutcome(
            text: text,
            systemPrompt: systemPrompt,
            temperature: temperature,
            openAIProvider: openAIProvider,
            groqProvider: groqProvider
        ).text
    }

    func completeWithOutcome(
        text: String,
        systemPrompt: String,
        temperature: Double,
        openAIProvider: LLMProvider,
        groqProvider: LLMProvider
    ) async throws -> Outcome {
        guard providerMode == .auto, hasGroqKey else {
            let result = try await openAIProvider.complete(text: text, systemPrompt: systemPrompt, temperature: temperature)
            return Outcome(text: result, provider: .openAI, model: openAIProvider.modelName)
        }

        do {
            let result = try await groqProvider.complete(text: text, systemPrompt: systemPrompt, temperature: temperature)
            return Outcome(text: result, provider: .groq, model: groqProvider.modelName)
        } catch {
            let result = try await openAIProvider.complete(text: text, systemPrompt: systemPrompt, temperature: temperature)
            return Outcome(text: result, provider: .openAI, model: openAIProvider.modelName)
        }
    }
}

enum LLMService {
    static func improve(
        text: String,
        settings: TextImprovementSettings,
        model: RewriteModel = .fastEdit,
        providerMode: RewriteProviderMode = .auto,
        hasGroqKey: Bool = KeychainService.load(key: .groqAPIKey) != nil
    ) async throws -> String {
        try await complete(
            text: text,
            systemPrompt: buildSystemPrompt(settings: settings),
            model: model,
            temperature: 0.3,
            providerMode: providerMode,
            hasGroqKey: hasGroqKey
        )
    }

    static func dampfAblassen(
        text: String,
        systemPrompt: String,
        model: RewriteModel = .rageMode,
        providerMode: RewriteProviderMode = .auto,
        hasGroqKey: Bool = KeychainService.load(key: .groqAPIKey) != nil
    ) async throws -> String {
        try await complete(
            text: text,
            systemPrompt: systemPrompt,
            model: model,
            temperature: 0.4,
            providerMode: providerMode,
            hasGroqKey: hasGroqKey
        )
    }

    static func addEmojis(
        text: String,
        settings: EmojiTextSettings,
        model: RewriteModel = .fastEdit,
        providerMode: RewriteProviderMode = .auto,
        hasGroqKey: Bool = KeychainService.load(key: .groqAPIKey) != nil
    ) async throws -> String {
        try await complete(
            text: text,
            systemPrompt: buildEmojiSystemPrompt(density: settings.emojiDensity),
            model: model,
            temperature: 0.3,
            providerMode: providerMode,
            hasGroqKey: hasGroqKey
        )
    }

    private static func complete(
        text: String,
        systemPrompt: String,
        model: RewriteModel,
        temperature: Double,
        providerMode: RewriteProviderMode,
        hasGroqKey: Bool
    ) async throws -> String {
        let router = ProviderRouter(providerMode: providerMode, hasGroqKey: hasGroqKey)
        return try await router.complete(
            text: text,
            systemPrompt: systemPrompt,
            temperature: temperature,
            openAIProvider: OpenAIProvider(model: model),
            groqProvider: GroqProvider()
        )
    }

    // MARK: - Local-first routing (#124)

    static func improveLocalFirst(
        text: String,
        settings: TextImprovementSettings,
        model: RewriteModel = .fastEdit,
        providerMode: RewriteProviderMode = .auto,
        hasGroqKey: Bool = KeychainService.load(key: .groqAPIKey) != nil,
        consent: RewriteConsentCoordinating
    ) async throws -> RewriteStepResult {
        try await completeLocalFirst(
            text: text,
            systemPrompt: buildSystemPrompt(settings: settings),
            workflow: .textImprover,
            model: model,
            temperature: 0.3,
            providerMode: providerMode,
            hasGroqKey: hasGroqKey,
            consent: consent
        )
    }

    static func dampfAblassenLocalFirst(
        text: String,
        systemPrompt: String,
        model: RewriteModel = .rageMode,
        providerMode: RewriteProviderMode = .auto,
        hasGroqKey: Bool = KeychainService.load(key: .groqAPIKey) != nil,
        consent: RewriteConsentCoordinating
    ) async throws -> RewriteStepResult {
        try await completeLocalFirst(
            text: text,
            systemPrompt: systemPrompt,
            workflow: .dampfAblassen,
            model: model,
            temperature: 0.4,
            providerMode: providerMode,
            hasGroqKey: hasGroqKey,
            consent: consent
        )
    }

    static func addEmojisLocalFirst(
        text: String,
        settings: EmojiTextSettings,
        model: RewriteModel = .fastEdit,
        providerMode: RewriteProviderMode = .auto,
        hasGroqKey: Bool = KeychainService.load(key: .groqAPIKey) != nil,
        consent: RewriteConsentCoordinating
    ) async throws -> RewriteStepResult {
        try await completeLocalFirst(
            text: text,
            systemPrompt: buildEmojiSystemPrompt(density: settings.emojiDensity),
            workflow: .emojiText,
            model: model,
            temperature: 0.3,
            providerMode: providerMode,
            hasGroqKey: hasGroqKey,
            consent: consent
        )
    }

    private static func completeLocalFirst(
        text: String,
        systemPrompt: String,
        workflow: WorkflowType,
        model: RewriteModel,
        temperature: Double,
        providerMode: RewriteProviderMode,
        hasGroqKey: Bool,
        consent: RewriteConsentCoordinating
    ) async throws -> RewriteStepResult {
        let router = RewriteRouter(providerMode: providerMode, hasGroqKey: hasGroqKey)
        let result = try await router.completeWithOutcome(
            text: text,
            systemPrompt: systemPrompt,
            temperature: temperature,
            workflow: workflow,
            appleProvider: RewriteRouter.resolveAppleProvider(),
            openAIProvider: OpenAIProvider(model: model),
            groqProvider: GroqProvider(),
            presentConsent: { reason, provider in
                await consent.presentConsent(reason: reason, provider: provider)
            },
            readConsent: consent.readConsent,
            writeConsent: consent.writeConsent
        )
        return RewriteStepResult(text: result.text, completionLabel: result.outcome.completionLabel)
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
