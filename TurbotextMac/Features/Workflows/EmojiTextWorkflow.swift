import Foundation

@MainActor
final class EmojiTextWorkflow: SpokenRewriteWorkflow {
    typealias Rewriter = (String, EmojiTextSettings, RewriteProviderMode) async throws -> String

    private let settings: EmojiTextSettings
    private let providerMode: RewriteProviderMode
    private let rewriter: Rewriter

    init(
        settings: EmojiTextSettings,
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
            try await LLMService.addEmojis(
                text: text,
                settings: settings,
                providerMode: providerMode
            )
        }
    ) {
        self.settings = settings
        self.providerMode = providerMode
        self.rewriter = rewriter
        super.init(
            type: .emojiText,
            customTerms: customTerms,
            language: language,
            rewritingMessage: "Emojis werden eingefügt ...",
            noSpeechSentinel: "KEINE_AUFNAHME_ERKANNT",
            pipeline: pipeline,
            transcriber: transcriber
        )
    }

    override func rewrite(_ transcript: String) async throws -> String {
        try await rewriter(transcript, settings, providerMode)
    }
}
