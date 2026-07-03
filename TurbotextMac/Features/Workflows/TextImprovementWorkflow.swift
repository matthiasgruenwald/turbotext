import Foundation

@MainActor
final class TextImprovementWorkflow: SpokenRewriteWorkflow {
    typealias Improver = (String, TextImprovementSettings, RewriteProviderMode) async throws -> String

    private let settings: TextImprovementSettings
    private let providerMode: RewriteProviderMode
    private let improver: Improver

    init(
        settings: TextImprovementSettings,
        language: String = "de",
        providerMode: RewriteProviderMode = .auto,
        pipeline: SpokenWorkflowPipeline? = nil,
        transcriber: @escaping SpokenWorkflowPipeline.Transcriber,
        improver: @escaping Improver = { text, settings, providerMode in
            try await LLMService.improve(
                text: text,
                settings: settings,
                providerMode: providerMode
            )
        }
    ) {
        self.settings = settings
        self.providerMode = providerMode
        self.improver = improver
        super.init(
            type: .textImprover,
            customTerms: settings.customTerms,
            language: language,
            rewritingMessage: "Text wird verbessert ...",
            pipeline: pipeline,
            transcriber: transcriber
        )
    }

    override func rewrite(_ transcript: String) async throws -> String {
        try await improver(transcript, settings, providerMode)
    }
}
