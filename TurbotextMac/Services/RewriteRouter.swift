import Foundation
import OSLog

private let rewriteLogger = Logger(subsystem: "app.turbotext.mac", category: "Rewrite")

/// The concrete online backend a rewrite request is routed to when `RewriteBackend.online`
/// is selected.
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

/// Which path actually completed a rewrite (#128), and the completion label to show in
/// the signal pill roughly 3s after the result is pasted.
enum RewriteOutcome: Equatable {
    case local(model: String)
    case online(provider: OnlineProvider, model: String)
    /// `RewriteBackend.aus`: raw, unmodified text was inserted because rewriting is
    /// switched off entirely — no LLM call was made (ADR 0013).
    case backendOff
    /// `RewriteBackend.lokal`: the on-device attempt failed for any reason (context
    /// window, guardrail violation, unavailability, or unusable output per #180) and
    /// silently fell back to the raw dictation text — never towards Online (ADR 0013).
    case localRewriteFailed

    var completionLabel: String? {
        switch self {
        case .local(let model):
            return "Text lokal verbessert · \(model)"
        case .online(let provider, let model):
            return "Text online verbessert · \(provider.displayName) · \(model)"
        case .backendOff:
            return RewriteStage.rawInsertionCompletionLabel
        case .localRewriteFailed:
            return "Nachbearbeitung fehlgeschlagen – Rohtext eingefügt"
        }
    }
}

/// Explicit backend routing for the three rewrite workflows (ADR 0013): the user picks
/// Aus/Lokal/Online up front in settings, replacing the previous local-first-with-
/// runtime-consent flow. No dialog, no persisted per-workflow decision — the settings
/// choice itself is the consent.
struct RewriteRouter {
    let backend: RewriteBackend
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

    /// The online provider used once `RewriteBackend.online` is selected. `.groq` mode
    /// with a Groq key prefers Groq; everything else uses OpenAI.
    static func configuredOnlineProvider(providerMode: RewriteProviderMode, hasGroqKey: Bool) -> OnlineProvider {
        providerMode == .groq && hasGroqKey ? .groq : .openAI
    }

    /// Predicted routing path, shown in the signal pill while a rewrite is processing
    /// (#128) — known synchronously since it only depends on the configured backend and
    /// provider, not on the (async) call's actual outcome.
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

    func completeWithOutcome(
        text: String,
        systemPrompt: String,
        temperature: Double,
        appleProvider: LLMProvider?,
        openAIProvider: LLMProvider,
        groqProvider: LLMProvider
    ) async throws -> (text: String, outcome: RewriteOutcome) {
        switch backend {
        case .aus:
            return (text, .backendOff)
        case .lokal:
            return try await completeLocal(
                text: text, systemPrompt: systemPrompt, temperature: temperature, appleProvider: appleProvider
            )
        case .online:
            // TODO(#198): real Online routing (Groq-first with silent OpenAI fallback on
            // provider failure, offline network falls back to Lokal then Rohtext — see
            // ADR 0013). Minimal passthrough for now so the backend switch stays
            // exhaustive: reuses the existing Groq/OpenAI auto-routing unchanged.
            return try await fallbackToExistingRouter(
                text: text, systemPrompt: systemPrompt, temperature: temperature,
                openAIProvider: openAIProvider, groqProvider: groqProvider
            )
        }
    }

    /// `RewriteBackend.lokal`: only ever tries the Apple provider. Any failure — no
    /// provider available, context window exceeded, guardrail violation, or output that
    /// fails `RewriteOutputValidator` (#180) — falls silently back to the raw dictation
    /// text. Never reaches for Online (ADR 0013).
    private func completeLocal(
        text: String,
        systemPrompt: String,
        temperature: Double,
        appleProvider: LLMProvider?
    ) async throws -> (text: String, outcome: RewriteOutcome) {
        guard let appleProvider else {
            return (text, .localRewriteFailed)
        }

        do {
            let result = try await appleProvider.complete(text: text, systemPrompt: systemPrompt, temperature: temperature)
            // The hypothetical no-speech sentinel must reach `RewriteStage` untouched,
            // which rejects it — validating it would misclassify it as unusable output (#180).
            if TranscriptionQualityService.cleanedTranscript(result) == RewriteStage.noSpeechSentinel {
                return (result, .local(model: appleProvider.modelName))
            }
            let failure = RewriteOutputValidator.validate(input: text, output: result, systemPrompt: systemPrompt)
            logLocalRewrite(inputLength: text.count, outputLength: result.count, failure: failure)
            guard failure == nil else {
                return (text, .localRewriteFailed)
            }
            return (result, .local(model: appleProvider.modelName))
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return (text, .localRewriteFailed)
        }
    }

    private func logLocalRewrite(inputLength: Int, outputLength: Int, failure: RewriteOutputFailure?) {
        let check = failure.map { String(describing: $0) } ?? "none"
        rewriteLogger.info("Local rewrite: input \(inputLength) chars, output \(outputLength) chars, check \(check, privacy: .public)")
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
}
