import Foundation

/// The concrete online backend a rewrite request can be routed to once the user
/// consents to leaving the device. Persisted per-workflow in `AppSettings.rewriteConsents`.
enum OnlineProvider: String, Codable, Equatable, CaseIterable {
    case groq
    case openAI

    var displayName: String {
        switch self {
        case .groq: return "Groq"
        case .openAI: return "OpenAI"
        }
    }
}

/// Why the on-device rewrite could not be completed locally, shown to the user in the
/// consent dialog alongside the concrete online provider that would handle the request.
enum RewriteConsentReason: Equatable {
    case contextWindowExceeded
    case guardrailViolation
    case onlineProviderFailed(OnlineProvider)

    var localizedDescription: String {
        switch self {
        case .contextWindowExceeded:
            return AppleRewriteError.contextWindowExceeded.localizedDescription
        case .guardrailViolation:
            return AppleRewriteError.guardrailViolation.localizedDescription
        case .onlineProviderFailed(let provider):
            return "\(provider.displayName) war gerade nicht erreichbar."
        }
    }
}

/// Local-first routing for the three rewrite workflows: prefers Apple's on-device
/// Foundation Models provider, and only reaches out online after explicit, per-workflow
/// user consent. Delegates to the unchanged `ProviderRouter` whenever on-device rewriting
/// isn't available at all, so devices without Apple Intelligence behave exactly as before.
struct RewriteRouter {
    enum ConsentDecision: Equatable {
        case insertRawText
        case continueOnline(remember: Bool)
    }

    typealias ConsentPresenter = @MainActor (RewriteConsentReason, OnlineProvider) async -> ConsentDecision
    typealias ConsentReader = (WorkflowType) -> OnlineProvider?
    typealias ConsentWriter = (WorkflowType, OnlineProvider?) -> Void

    let providerMode: RewriteProviderMode
    let hasGroqKey: Bool

    /// Resolves the on-device provider for production call sites, or `nil` on devices
    /// below macOS 26 or without Apple Intelligence available. Tests inject their own
    /// `appleProvider` directly instead of going through this.
    static func resolveAppleProvider() -> LLMProvider? {
        guard #available(macOS 26, *) else { return nil }
        guard AppleFoundationModelsProvider.isAvailable else { return nil }
        return AppleFoundationModelsProvider()
    }

    /// The online provider named in the consent dialog and used once consent is granted.
    /// Auto mode with a Groq key prefers Groq; everything else uses OpenAI.
    static func configuredOnlineProvider(providerMode: RewriteProviderMode, hasGroqKey: Bool) -> OnlineProvider {
        providerMode == .auto && hasGroqKey ? .groq : .openAI
    }

    func complete(
        text: String,
        systemPrompt: String,
        temperature: Double,
        workflow: WorkflowType,
        appleProvider: LLMProvider?,
        openAIProvider: LLMProvider,
        groqProvider: LLMProvider,
        presentConsent: @escaping ConsentPresenter,
        readConsent: @escaping ConsentReader,
        writeConsent: @escaping ConsentWriter
    ) async throws -> String {
        guard let appleProvider else {
            return try await fallbackToExistingRouter(
                text: text, systemPrompt: systemPrompt, temperature: temperature,
                openAIProvider: openAIProvider, groqProvider: groqProvider
            )
        }

        do {
            return try await appleProvider.complete(text: text, systemPrompt: systemPrompt, temperature: temperature)
        } catch let error as AppleRewriteError {
            switch error {
            case .unavailable:
                return try await fallbackToExistingRouter(
                    text: text, systemPrompt: systemPrompt, temperature: temperature,
                    openAIProvider: openAIProvider, groqProvider: groqProvider
                )
            case .contextWindowExceeded:
                return try await resolveViaConsent(
                    reason: .contextWindowExceeded, text: text, systemPrompt: systemPrompt, temperature: temperature,
                    workflow: workflow, openAIProvider: openAIProvider, groqProvider: groqProvider,
                    presentConsent: presentConsent, readConsent: readConsent, writeConsent: writeConsent
                )
            case .guardrailViolation:
                return try await resolveViaConsent(
                    reason: .guardrailViolation, text: text, systemPrompt: systemPrompt, temperature: temperature,
                    workflow: workflow, openAIProvider: openAIProvider, groqProvider: groqProvider,
                    presentConsent: presentConsent, readConsent: readConsent, writeConsent: writeConsent
                )
            }
        }
    }

    private func fallbackToExistingRouter(
        text: String,
        systemPrompt: String,
        temperature: Double,
        openAIProvider: LLMProvider,
        groqProvider: LLMProvider
    ) async throws -> String {
        try await ProviderRouter(providerMode: providerMode, hasGroqKey: hasGroqKey).complete(
            text: text,
            systemPrompt: systemPrompt,
            temperature: temperature,
            openAIProvider: openAIProvider,
            groqProvider: groqProvider
        )
    }

    private func resolveViaConsent(
        reason: RewriteConsentReason,
        text: String,
        systemPrompt: String,
        temperature: Double,
        workflow: WorkflowType,
        openAIProvider: LLMProvider,
        groqProvider: LLMProvider,
        presentConsent: @escaping ConsentPresenter,
        readConsent: @escaping ConsentReader,
        writeConsent: @escaping ConsentWriter
    ) async throws -> String {
        let expectedProvider = Self.configuredOnlineProvider(providerMode: providerMode, hasGroqKey: hasGroqKey)

        if let stored = readConsent(workflow) {
            if stored == expectedProvider {
                return try await completeOnline(
                    provider: stored, text: text, systemPrompt: systemPrompt, temperature: temperature,
                    workflow: workflow, openAIProvider: openAIProvider, groqProvider: groqProvider,
                    presentConsent: presentConsent, writeConsent: writeConsent
                )
            }
            // The configured online provider changed since consent was granted; discard
            // the stale consent and ask again for the currently configured provider.
            writeConsent(workflow, nil)
        }

        switch await presentConsent(reason, expectedProvider) {
        case .insertRawText:
            return text
        case .continueOnline(let remember):
            if remember { writeConsent(workflow, expectedProvider) }
            return try await completeOnline(
                provider: expectedProvider, text: text, systemPrompt: systemPrompt, temperature: temperature,
                workflow: workflow, openAIProvider: openAIProvider, groqProvider: groqProvider,
                presentConsent: presentConsent, writeConsent: writeConsent
            )
        }
    }

    /// Routes to the consented provider. Groq gets no silent fallback on failure — per
    /// the product spec, a Groq failure re-prompts the consent dialog with OpenAI as the
    /// offered provider instead of quietly switching backends.
    private func completeOnline(
        provider: OnlineProvider,
        text: String,
        systemPrompt: String,
        temperature: Double,
        workflow: WorkflowType,
        openAIProvider: LLMProvider,
        groqProvider: LLMProvider,
        presentConsent: @escaping ConsentPresenter,
        writeConsent: @escaping ConsentWriter
    ) async throws -> String {
        switch provider {
        case .openAI:
            return try await openAIProvider.complete(text: text, systemPrompt: systemPrompt, temperature: temperature)
        case .groq:
            do {
                return try await groqProvider.complete(text: text, systemPrompt: systemPrompt, temperature: temperature)
            } catch {
                switch await presentConsent(.onlineProviderFailed(.groq), .openAI) {
                case .insertRawText:
                    return text
                case .continueOnline(let remember):
                    if remember { writeConsent(workflow, .openAI) }
                    return try await openAIProvider.complete(text: text, systemPrompt: systemPrompt, temperature: temperature)
                }
            }
        }
    }
}
