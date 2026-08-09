import Foundation

/// What building a workflow instance produced (#192) — mirrors `WorkflowStartOutcome`
/// (#190) but carries the workflow itself, since this is the layer that creates it. No
/// workflow is constructed on `.rejected`, so audio capture can never start for a start
/// attempt that ends up here.
enum WorkflowBuildResult {
    case workflow(any Workflow)
    case rejected(WorkflowStartRejection)
}

/// Builds the four spoken workflows for a given `WorkflowType` (#191, prefactor split out
/// of `AppState`, blocked by and following #190). Constructible without the central app
/// state: settings travel in per call as `Settings`, everything else — Sprachasset-
/// Bereitschaft, transcriber resolution, orchestration callbacks — is injected at
/// construction.
///
/// #192 collapsed the four near-identical live/file branches (Transkription, Turbotext+,
/// Dampf ablassen, Emoji-Text) into one: `buildSpokenWorkflow` applies the live rule and
/// the transcriber resolution exactly once, then reads a `SpokenWorkflowSpec` — data, not
/// code — for what differs per type (messages, rewrite step, whether smoothing applies).
/// A resolution of "unavailable" now yields a rejection through the same result shape
/// `WorkflowLifecycleManager` already used for the pre-flight start gate (#190), instead of
/// a workflow whose transcriber only throws once actually invoked after a recording.
@MainActor
struct WorkflowFactory {

    /// What `resolveTranscriber` hands back for a workflow to run with.
    struct ResolvedTranscriber {
        /// `nil` exactly when `resolution == .unavailable` — nothing to run.
        let transcriber: SpokenWorkflowPipeline.Transcriber?
        let backend: TranscriptionBackend
        let resolution: ResolvedTranscriptionBackend
        /// Populated when `resolution == .unavailable`: why, and whether pressing the
        /// shortcut again has a realistic chance of working (e.g. Sprachasset install
        /// already underway). `nil` for every other resolution.
        let unavailableRejection: WorkflowStartRejection?
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
    /// `TranscriptionBackendResolver` plus live network/quota/model state. No longer takes
    /// a backend override (#193): the legacy-WhisperKit rule is derived from settings inside
    /// the resolver itself, so every call decides the same thing regardless of caller.
    let resolveTranscriber: () -> ResolvedTranscriber
    /// The always-local transcriber for `.localTranscription`, which never goes through
    /// backend resolution.
    let localTranscriber: () -> SpokenWorkflowPipeline.Transcriber
    /// Kicks off Sprachasset-Bereitschaft securing on demand (#189/#190) — wired by
    /// `resolveTranscriber`'s caller when assets aren't ready yet, regardless of whether
    /// the resulting workflow will run live or file-based (#192, fixes F2 from #188).
    let secureAppleSpeechAssetsOnDemand: () -> Void
    let onLiveTranscriptUpdate: (LiveTranscriptDisplay) -> Void
    let onBergung: (String?) -> Void
    /// Predicted processing-label routing for the signal pill (#128) — a closure so it's
    /// evaluated fresh at call time, not frozen into `Settings` at build time.
    let rewriteProcessingLabel: () -> String?
    /// Current network quality (#198), read fresh at call time — production wires this to
    /// `NetworkPingService.status`. Consulted by `RewriteRouter` only for
    /// `RewriteBackend.online`, where `.red` means a real outage.
    let networkStatus: () -> NetworkQualityStatus

    func build(
        _ type: WorkflowType,
        settings: Settings
    ) -> WorkflowBuildResult {
        switch type {
        case .transcription, .textImprover, .dampfAblassen, .emojiText:
            return buildSpokenWorkflow(type, settings: settings)
        case .localTranscription:
            return .workflow(TranscriptionWorkflow(
                type: .localTranscription,
                customTerms: settings.textImprovementSettings.customTerms,
                language: settings.transcriptionSettings.language,
                backend: .local,
                transcriber: localTranscriber()
            ))
        }
    }

    /// Live rule (F1, #182): the live-dictation path is taken only when the backend
    /// resolution is Apple Speech and macOS 26 is available. Single source of truth —
    /// applied once here for all four spoken-workflow types (#192).
    static func routesToLiveDictation(_ resolution: ResolvedTranscriptionBackend) -> Bool {
        guard resolution == .appleSpeech else { return false }
        if #available(macOS 26, *) { return true }
        return false
    }

    /// What differs between the four spoken-workflow types — data read by
    /// `buildSpokenWorkflow`, which is otherwise identical for all four (#192).
    private struct SpokenWorkflowSpec {
        /// Live-path smoothing only ever applies to plain transcription — the three
        /// rewrite workflows wire a `RewriteStage` instead.
        let smoothingEnabled: Bool
        let rewritingMessage: String
        let noSpeechSentinel: String?
        /// `nil` for plain transcription, which has no rewrite step.
        let rewrite: ((Settings) -> (String) async throws -> RewriteStepResult)?
    }

    private func spec(for type: WorkflowType) -> SpokenWorkflowSpec {
        switch type {
        case .transcription:
            return SpokenWorkflowSpec(
                smoothingEnabled: true,
                rewritingMessage: "Wird verarbeitet ...",
                noSpeechSentinel: nil,
                rewrite: nil
            )
        case .textImprover:
            return SpokenWorkflowSpec(
                smoothingEnabled: false,
                rewritingMessage: "Text wird verbessert ...",
                noSpeechSentinel: nil,
                rewrite: { settings in
                    let textSettings = settings.textImprovementSettings
                    let providerMode = settings.appSettings.rewritingProviderMode
                    let backend = settings.appSettings.rewriteBackend
                    return { text in
                        try await LLMService.improveLocalFirst(
                            text: text,
                            settings: textSettings,
                            providerMode: providerMode,
                            backend: backend,
                            networkStatus: networkStatus
                        )
                    }
                }
            )
        case .dampfAblassen:
            return SpokenWorkflowSpec(
                smoothingEnabled: false,
                rewritingMessage: "Wird umformuliert ...",
                noSpeechSentinel: RewriteStage.noSpeechSentinel,
                rewrite: { settings in
                    let dampfSettings = settings.dampfAblassenSettings
                    let providerMode = settings.appSettings.rewritingProviderMode
                    let backend = settings.appSettings.rewriteBackend
                    return { text in
                        try await LLMService.dampfAblassenLocalFirst(
                            text: text,
                            systemPrompt: dampfSettings.systemPrompt,
                            providerMode: providerMode,
                            backend: backend,
                            networkStatus: networkStatus
                        )
                    }
                }
            )
        case .emojiText:
            return SpokenWorkflowSpec(
                smoothingEnabled: false,
                rewritingMessage: "Emojis werden eingefügt ...",
                noSpeechSentinel: RewriteStage.noSpeechSentinel,
                rewrite: { settings in
                    let emojiSettings = settings.emojiTextSettings
                    let providerMode = settings.appSettings.rewritingProviderMode
                    let backend = settings.appSettings.rewriteBackend
                    return { text in
                        try await LLMService.addEmojisLocalFirst(
                            text: text,
                            settings: emojiSettings,
                            providerMode: providerMode,
                            backend: backend,
                            networkStatus: networkStatus
                        )
                    }
                }
            )
        case .localTranscription:
            preconditionFailure("localTranscription never resolves a transcriber, so it never reaches buildSpokenWorkflow")
        }
    }

    /// Fallback rejection for the (in practice unreachable) case where a resolution
    /// reports "unavailable" without a specific reason attached.
    private static let genericUnavailableRejection = WorkflowStartRejection(
        reason: "unavailable",
        message: "Transkription derzeit nicht verfügbar.",
        canRetryImmediately: false
    )

    private func buildSpokenWorkflow(
        _ type: WorkflowType,
        settings: Settings
    ) -> WorkflowBuildResult {
        let spec = spec(for: type)
        let resolved = resolveTranscriber()

        guard resolved.resolution != .unavailable, let transcriber = resolved.transcriber else {
            return .rejected(resolved.unavailableRejection ?? Self.genericUnavailableRejection)
        }

        if Self.routesToLiveDictation(resolved.resolution), #available(macOS 26, *),
           let liveWorkflow = buildLiveWorkflow(type: type, spec: spec, settings: settings) {
            return .workflow(liveWorkflow)
        }
        return .workflow(buildFileBasedWorkflow(
            type: type, spec: spec, transcriber: transcriber, backend: resolved.backend, settings: settings
        ))
    }

    /// `nil` only when `spec` has neither smoothing nor a rewrite step wired — doesn't
    /// happen for any of the four spoken types today, but keeps this function honest
    /// about not being able to build a live workflow out of nothing.
    @available(macOS 26, *)
    private func buildLiveWorkflow(type: WorkflowType, spec: SpokenWorkflowSpec, settings: Settings) -> (any Workflow)? {
        if spec.smoothingEnabled {
            let smoothing = liveDictationSmoothing(settings: settings)
            return makeLiveDictationWorkflow(
                type: type, settings: settings, smoothingPass: smoothing.pass, smoothingMessage: smoothing.message
            )
        }
        guard let makeRewrite = spec.rewrite else { return nil }
        let rewrite = makeRewrite(settings)
        return makeLiveDictationWorkflow(
            type: type,
            settings: settings,
            rewritingMessage: spec.rewritingMessage,
            rewriteStage: RewriteStage(noSpeechSentinel: spec.noSpeechSentinel, rewrite: rewrite),
            processingLabelResolver: rewriteProcessingLabel
        )
    }

    private func buildFileBasedWorkflow(
        type: WorkflowType,
        spec: SpokenWorkflowSpec,
        transcriber: @escaping SpokenWorkflowPipeline.Transcriber,
        backend: TranscriptionBackend,
        settings: Settings
    ) -> any Workflow {
        guard let makeRewrite = spec.rewrite else {
            return TranscriptionWorkflow(
                customTerms: settings.textImprovementSettings.customTerms,
                language: settings.transcriptionSettings.language,
                backend: backend,
                transcriber: transcriber
            )
        }
        let rewrite = makeRewrite(settings)
        return SpokenRewriteWorkflow(
            type: type,
            customTerms: settings.textImprovementSettings.customTerms,
            language: settings.transcriptionSettings.language,
            rewritingMessage: spec.rewritingMessage,
            noSpeechSentinel: spec.noSpeechSentinel,
            transcriber: transcriber,
            processingLabelResolver: rewriteProcessingLabel,
            rewrite: rewrite
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
