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

/// Which path actually completed a rewrite (#128), and the completion label to show in
/// the signal pill roughly 3s after the result is pasted.
enum RewriteOutcome: Equatable {
    case local(model: String)
    case online(provider: OnlineProvider, model: String)
    /// Raw, unmodified text was inserted (user declined the consent dialog) — nothing
    /// was actually improved, so no completion label is shown.
    case rawTextInserted

    var completionLabel: String? {
        switch self {
        case .local(let model):
            return "Text lokal verbessert · \(model)"
        case .online(let provider, let model):
            return "Text online verbessert · \(provider.displayName) · \(model)"
        case .rawTextInserted:
            return nil
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

    /// Predicted routing path, shown in the signal pill while a rewrite is processing
    /// (#128) — known synchronously since it only depends on Apple provider availability
    /// and the configured online provider, not on the (async) call's actual outcome.
    static func processingLabel(
        appleProviderAvailable: Bool,
        providerMode: RewriteProviderMode,
        hasGroqKey: Bool
    ) -> String {
        guard appleProviderAvailable else {
            let provider = configuredOnlineProvider(providerMode: providerMode, hasGroqKey: hasGroqKey)
            return "Nachbearbeitung läuft online mit \(provider.displayName)"
        }
        return "Nachbearbeitung läuft – lokal auf diesem Mac"
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
        try await completeWithOutcome(
            text: text, systemPrompt: systemPrompt, temperature: temperature, workflow: workflow,
            appleProvider: appleProvider, openAIProvider: openAIProvider, groqProvider: groqProvider,
            presentConsent: presentConsent, readConsent: readConsent, writeConsent: writeConsent
        ).text
    }

    func completeWithOutcome(
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
    ) async throws -> (text: String, outcome: RewriteOutcome) {
        guard let appleProvider else {
            return try await fallbackToExistingRouter(
                text: text, systemPrompt: systemPrompt, temperature: temperature,
                openAIProvider: openAIProvider, groqProvider: groqProvider
            )
        }

        do {
            let result = try await appleProvider.complete(text: text, systemPrompt: systemPrompt, temperature: temperature)
            return (result, .local(model: appleProvider.modelName))
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
    ) async throws -> (text: String, outcome: RewriteOutcome) {
        let outcome = try await ProviderRouter(providerMode: providerMode, hasGroqKey: hasGroqKey).completeWithOutcome(
            text: text,
            systemPrompt: systemPrompt,
            temperature: temperature,
            openAIProvider: openAIProvider,
            groqProvider: groqProvider
        )
        return (outcome.text, .online(provider: outcome.provider, model: outcome.model))
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
    ) async throws -> (text: String, outcome: RewriteOutcome) {
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
            return (text, .rawTextInserted)
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
    ) async throws -> (text: String, outcome: RewriteOutcome) {
        switch provider {
        case .openAI:
            let result = try await openAIProvider.complete(text: text, systemPrompt: systemPrompt, temperature: temperature)
            return (result, .online(provider: .openAI, model: openAIProvider.modelName))
        case .groq:
            do {
                let result = try await groqProvider.complete(text: text, systemPrompt: systemPrompt, temperature: temperature)
                return (result, .online(provider: .groq, model: groqProvider.modelName))
            } catch {
                switch await presentConsent(.onlineProviderFailed(.groq), .openAI) {
                case .insertRawText:
                    return (text, .rawTextInserted)
                case .continueOnline(let remember):
                    if remember { writeConsent(workflow, .openAI) }
                    let result = try await openAIProvider.complete(text: text, systemPrompt: systemPrompt, temperature: temperature)
                    return (result, .online(provider: .openAI, model: openAIProvider.modelName))
                }
            }
        }
    }
}
