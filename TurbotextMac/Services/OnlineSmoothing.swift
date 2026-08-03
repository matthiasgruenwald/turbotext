import Foundation

/// System instruction shared by both smoothing backends (#170), so on-device and
/// online passes smooth identically.
enum SmoothingPrompt {
    static let systemInstruction = """
        Du glaettest ein Diktat: korrigiere Satzzeichen, Gross-/Kleinschreibung und \
        offensichtliche Erkennungsfehler. Behalte Bedeutung und Wortlaut moeglichst bei. \
        Gib NUR den geglaetteten Text zurueck, keine Erklaerungen.
        """
}

/// Online smoothing for the live dictation (#170): follows the rewrite workflows'
/// provider routing (`rewritingProviderMode`, ADR-0001 pattern) and fails silently
/// to `nil`, which is exactly the budget race's lost-pass path — the raw text gets
/// inserted instead (ADR 0007).
struct OnlineSmoothing {
    let providerMode: RewriteProviderMode
    let hasGroqKey: Bool

    /// The provider named in the signal pill while the pass runs. Predicted from the
    /// settings, not the call outcome — same pattern as `RewriteRouter.processingLabel`.
    var predictedProvider: OnlineProvider {
        RewriteRouter.configuredOnlineProvider(providerMode: providerMode, hasGroqKey: hasGroqKey)
    }

    func smooth(text: String) async -> String? {
        await smooth(
            text: text,
            openAIProvider: OpenAIProvider(model: .fastEdit),
            groqProvider: GroqProvider()
        )
    }

    func smooth(text: String, openAIProvider: LLMProvider, groqProvider: LLMProvider) async -> String? {
        let router = ProviderRouter(providerMode: providerMode, hasGroqKey: hasGroqKey)
        do {
            let result = try await router.complete(
                text: text,
                systemPrompt: SmoothingPrompt.systemInstruction,
                temperature: 0.1,
                openAIProvider: openAIProvider,
                groqProvider: groqProvider
            )
            let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        } catch {
            return nil
        }
    }
}
