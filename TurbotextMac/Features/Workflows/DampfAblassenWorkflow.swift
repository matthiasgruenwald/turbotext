import Foundation

@MainActor
final class DampfAblassenWorkflow: SpokenRewriteWorkflow {
    typealias Rewriter = (String, DampfAblassenSettings, RewriteProviderMode) async throws -> String

    private let settings: DampfAblassenSettings
    private let providerMode: RewriteProviderMode
    private let rewriter: Rewriter

    init(
        settings: DampfAblassenSettings,
        customTerms: [String] = [],
        language: String = "de",
        providerMode: RewriteProviderMode = .auto,
        pipeline: SpokenWorkflowPipeline? = nil,
        transcriber: @escaping SpokenWorkflowPipeline.Transcriber = { audioURL, duration, terms, language in
            try await TranscriptionService.transcribe(
                audioURL: audioURL,
                durationSeconds: duration,
                customTerms: terms,
                language: language
            ).text
        },
        rewriter: @escaping Rewriter = { text, settings, providerMode in
            try await LLMService.dampfAblassen(
                text: text,
                systemPrompt: settings.systemPrompt,
                providerMode: providerMode
            )
        }
    ) {
        self.settings = settings
        self.providerMode = providerMode
        self.rewriter = rewriter
        super.init(
            type: .dampfAblassen,
            customTerms: customTerms,
            language: language,
            rewritingMessage: "Wird umformuliert ...",
            noSpeechSentinel: "KEINE_AUFNAHME_ERKANNT",
            pipeline: pipeline,
            transcriber: transcriber
        )
    }

    override func rewrite(_ transcript: String) async throws -> String {
        try await rewriter(transcript, settings, providerMode)
    }
}
