import Foundation

/// Builds the four spoken workflows for a given `WorkflowType` (#191, prefactor split out
/// of `AppState`, blocked by and following #190). Constructible without the central app
/// state: settings travel in per call as `Settings`, everything else — Sprachasset-
/// Bereitschaft, transcriber resolution, orchestration callbacks — is injected at
/// construction. "Make the change easy, then make the easy change" — this ticket only
/// relocates existing behavior; #192 changes it.
@MainActor
struct WorkflowFactory {

    /// What `resolveTranscriber` hands back for a workflow to run with.
    struct ResolvedTranscriber {
        let transcriber: SpokenWorkflowPipeline.Transcriber
        let backend: TranscriptionBackend
        let resolution: ResolvedTranscriptionBackend
    }

    /// Settings snapshot a single `build` call needs — read fresh by the caller right
    /// before building, since the underlying settings can change between calls.
    struct Settings {
        let appSettings: AppSettings
        let transcriptionSettings: TranscriptionSettings
        let textImprovementSettings: TextImprovementSettings
        let dampfAblassenSettings: DampfAblassenSettings
        let emojiTextSettings: EmojiTextSettings
    }

    /// Full backend resolution (Apple Speech / remote / WhisperKit / unavailable) for the
    /// four cloud-capable spoken workflows — owned by the caller since it needs
    /// `TranscriptionBackendResolver` plus live network/quota/model state.
    let resolveTranscriber: (TranscriptionBackend?) -> ResolvedTranscriber
    /// The always-local transcriber for `.localTranscription`, which never goes through
    /// backend resolution.
    let localTranscriber: () -> SpokenWorkflowPipeline.Transcriber
    let rewriteConsentCoordinator: RewriteConsentCoordinating
    /// Kicks off Sprachasset-Bereitschaft securing on demand (#189/#190) — wired by the
    /// live session's early check when assets aren't ready yet.
    let secureAppleSpeechAssetsOnDemand: () -> Void
    let onLiveTranscriptUpdate: (LiveTranscriptDisplay) -> Void
    let onBergung: (String?) -> Void
    /// Predicted processing-label routing for the signal pill (#128) — a closure so it's
    /// evaluated fresh at call time, not frozen into `Settings` at build time.
    let rewriteProcessingLabel: () -> String?

    func build(
        _ type: WorkflowType,
        backendOverride: TranscriptionBackend?,
        settings: Settings
    ) -> (any Workflow)? {
        switch type {
        case .transcription:
            let resolved = resolveTranscriber(backendOverride)
            if Self.routesToLiveDictation(resolved.resolution), #available(macOS 26, *) {
                let smoothing = liveDictationSmoothing(settings: settings)
                return makeLiveDictationWorkflow(
                    type: .transcription,
                    settings: settings,
                    smoothingPass: smoothing.pass,
                    smoothingMessage: smoothing.message
                )
            }
            return TranscriptionWorkflow(
                customTerms: settings.textImprovementSettings.customTerms,
                language: settings.transcriptionSettings.language,
                backend: resolved.backend,
                transcriber: resolved.transcriber
            )
        case .localTranscription:
            return TranscriptionWorkflow(
                type: .localTranscription,
                customTerms: settings.textImprovementSettings.customTerms,
                language: settings.transcriptionSettings.language,
                backend: .local,
                transcriber: localTranscriber()
            )
        case .textImprover:
            return makeTextImproverWorkflow(settings: settings)
        case .dampfAblassen:
            return makeDampfAblassenWorkflow(settings: settings)
        case .emojiText:
            return makeEmojiTextWorkflow(settings: settings)
        }
    }

    /// Live rule (F1, #182): the live-dictation path is taken only when the backend
    /// resolution is Apple Speech and macOS 26 is available. Single source of truth —
    /// #186/#187 route the three rewrite workflows through the same predicate.
    static func routesToLiveDictation(_ resolution: ResolvedTranscriptionBackend) -> Bool {
        guard resolution == .appleSpeech else { return false }
        if #available(macOS 26, *) { return true }
        return false
    }

    private func makeTextImproverWorkflow(settings: Settings) -> any Workflow {
        let improver: SpokenRewriteWorkflow.Improver = { [rewriteConsentCoordinator] text, textSettings, providerMode in
            try await LLMService.improveLocalFirst(
                text: text,
                settings: textSettings,
                providerMode: providerMode,
                consent: rewriteConsentCoordinator
            )
        }
        let resolved = resolveTranscriber(nil)
        if Self.routesToLiveDictation(resolved.resolution), #available(macOS 26, *) {
            let textImprovementSettings = settings.textImprovementSettings
            let providerMode = settings.appSettings.rewritingProviderMode
            return makeLiveDictationWorkflow(
                type: .textImprover,
                settings: settings,
                rewritingMessage: "Text wird verbessert ...",
                rewriteStage: RewriteStage { text in
                    try await improver(text, textImprovementSettings, providerMode)
                },
                processingLabelResolver: rewriteProcessingLabel
            )
        }
        return SpokenRewriteWorkflow.textImprovement(
            settings: settings.textImprovementSettings,
            language: settings.transcriptionSettings.language,
            providerMode: settings.appSettings.rewritingProviderMode,
            transcriber: resolved.transcriber,
            processingLabelResolver: rewriteProcessingLabel,
            improver: improver
        )
    }

    private func makeDampfAblassenWorkflow(settings: Settings) -> any Workflow {
        let rewriter: SpokenRewriteWorkflow.DampfAblassenRewriter = { [rewriteConsentCoordinator] text, dampfSettings, providerMode in
            try await LLMService.dampfAblassenLocalFirst(
                text: text,
                systemPrompt: dampfSettings.systemPrompt,
                providerMode: providerMode,
                consent: rewriteConsentCoordinator
            )
        }
        let resolved = resolveTranscriber(nil)
        if Self.routesToLiveDictation(resolved.resolution), #available(macOS 26, *) {
            let dampfAblassenSettings = settings.dampfAblassenSettings
            let providerMode = settings.appSettings.rewritingProviderMode
            return makeLiveDictationWorkflow(
                type: .dampfAblassen,
                settings: settings,
                rewritingMessage: "Wird umformuliert ...",
                rewriteStage: RewriteStage(noSpeechSentinel: RewriteStage.noSpeechSentinel) { text in
                    try await rewriter(text, dampfAblassenSettings, providerMode)
                },
                processingLabelResolver: rewriteProcessingLabel
            )
        }
        return SpokenRewriteWorkflow.dampfAblassen(
            settings: settings.dampfAblassenSettings,
            customTerms: settings.textImprovementSettings.customTerms,
            language: settings.transcriptionSettings.language,
            providerMode: settings.appSettings.rewritingProviderMode,
            transcriber: resolved.transcriber,
            processingLabelResolver: rewriteProcessingLabel,
            rewriter: rewriter
        )
    }

    private func makeEmojiTextWorkflow(settings: Settings) -> any Workflow {
        let rewriter: SpokenRewriteWorkflow.EmojiTextRewriter = { [rewriteConsentCoordinator] text, emojiSettings, providerMode in
            try await LLMService.addEmojisLocalFirst(
                text: text,
                settings: emojiSettings,
                providerMode: providerMode,
                consent: rewriteConsentCoordinator
            )
        }
        let resolved = resolveTranscriber(nil)
        if Self.routesToLiveDictation(resolved.resolution), #available(macOS 26, *) {
            let emojiTextSettings = settings.emojiTextSettings
            let providerMode = settings.appSettings.rewritingProviderMode
            return makeLiveDictationWorkflow(
                type: .emojiText,
                settings: settings,
                rewritingMessage: "Emojis werden eingefügt ...",
                rewriteStage: RewriteStage(noSpeechSentinel: RewriteStage.noSpeechSentinel) { text in
                    try await rewriter(text, emojiTextSettings, providerMode)
                },
                processingLabelResolver: rewriteProcessingLabel
            )
        }
        return SpokenRewriteWorkflow.emojiText(
            settings: settings.emojiTextSettings,
            customTerms: settings.textImprovementSettings.customTerms,
            language: settings.transcriptionSettings.language,
            providerMode: settings.appSettings.rewritingProviderMode,
            transcriber: resolved.transcriber,
            processingLabelResolver: rewriteProcessingLabel,
            rewriter: rewriter
        )
    }

    @available(macOS 26, *)
    private func liveDictationSmoothing(settings: Settings) -> (pass: (@Sendable (String) async -> String?)?, message: String) {
        var pass: (@Sendable (String) async -> String?)?
        var message = "Glättet ..."
        switch settings.transcriptionSettings.liveSmoothingBackend {
        case .off:
            break
        case .onDevice:
            if FoundationModelsSmoothing.isAvailable {
                let smoothing = FoundationModelsSmoothing()
                pass = { text in await smoothing.smooth(text: text) }
                message = "Glättet lokal auf diesem Mac ..."
            }
        case .online:
            let smoothing = OnlineSmoothing(
                providerMode: settings.appSettings.rewritingProviderMode,
                hasGroqKey: KeychainService.load(key: .groqAPIKey) != nil
            )
            pass = { text in await smoothing.smooth(text: text) }
            message = "Glättet online mit \(smoothing.predictedProvider.displayName) ..."
        }
        return (pass, message)
    }

    @available(macOS 26, *)
    private func makeLiveDictationWorkflow(
        type: WorkflowType,
        settings: Settings,
        smoothingPass: (@Sendable (String) async -> String?)? = nil,
        smoothingMessage: String = "Glättet ...",
        rewritingMessage: String = "Wird verarbeitet ...",
        rewriteStage: RewriteStage? = nil,
        processingLabelResolver: @escaping () -> String? = { nil }
    ) -> any Workflow {
        let session = LiveTranscriptionSession(startAssetInstallation: { [secureAppleSpeechAssetsOnDemand] in
            Task { @MainActor in secureAppleSpeechAssetsOnDemand() }
        })
        return LiveDictationWorkflow(
            type: type,
            session: session,
            smoothingPass: smoothingPass,
            smoothingMessage: smoothingMessage,
            maxLines: settings.transcriptionSettings.livePillMaxLines,
            rewritingMessage: rewritingMessage,
            rewriteStage: rewriteStage,
            processingLabelResolver: processingLabelResolver,
            onLiveTranscriptUpdate: onLiveTranscriptUpdate,
            onBergung: onBergung
        )
    }
}
