import XCTest
@testable import Turbotext

@MainActor
final class RewriteRouterTests: XCTestCase {

    private struct FakeProvider: LLMProvider {
        let result: Result<String, Error>
        var onCalled: (() -> Void)?
        var modelName: String = "fake-model"

        func complete(text: String, systemPrompt: String, temperature: Double) async throws -> String {
            onCalled?()
            return try result.get()
        }
    }

    private func makeRouter(
        backend: RewriteBackend,
        providerMode: RewriteProviderMode = .groq,
        hasGroqKey: Bool = true
    ) -> RewriteRouter {
        RewriteRouter(backend: backend, providerMode: providerMode, hasGroqKey: hasGroqKey)
    }

    private func complete(
        _ router: RewriteRouter,
        text: String = "roher text",
        appleProvider: LLMProvider?,
        openAIProvider: LLMProvider = FakeProvider(result: .success("OpenAI-Ergebnis")),
        groqProvider: LLMProvider = FakeProvider(result: .success("Groq-Ergebnis"))
    ) async throws -> (text: String, outcome: RewriteOutcome) {
        try await router.completeWithOutcome(
            text: text,
            systemPrompt: "system",
            temperature: 0.3,
            appleProvider: appleProvider,
            openAIProvider: openAIProvider,
            groqProvider: groqProvider
        )
    }

    // MARK: - Aus (ADR 0013): immediate raw text, no LLM call at all

    func testAusReturnsRawTextImmediatelyWithoutCallingAnyProvider() async throws {
        var appleCalled = false
        var openAICalled = false
        var groqCalled = false

        let result = try await complete(
            makeRouter(backend: .aus),
            text: "unveraendert",
            appleProvider: FakeProvider(result: .success("sollte nie aufgerufen werden")) { appleCalled = true },
            openAIProvider: FakeProvider(result: .success("x")) { openAICalled = true },
            groqProvider: FakeProvider(result: .success("y")) { groqCalled = true }
        )

        XCTAssertEqual(result.text, "unveraendert")
        XCTAssertEqual(result.outcome, .backendOff)
        XCTAssertFalse(appleCalled)
        XCTAssertFalse(openAICalled)
        XCTAssertFalse(groqCalled)
    }

    func testAusCompletionLabelReusesShortInputRawInsertionLabel() async throws {
        let result = try await complete(makeRouter(backend: .aus), appleProvider: nil)

        XCTAssertEqual(result.outcome.completionLabel, RewriteStage.rawInsertionCompletionLabel)
    }

    // MARK: - Lokal (ADR 0013): only ever tries Apple, silent raw-text fallback on any error

    func testLokalSuccessReturnsLocalOutcomeWithoutTouchingOnlineProviders() async throws {
        var openAICalled = false
        var groqCalled = false

        let result = try await complete(
            makeRouter(backend: .lokal),
            text: "das meeting morgen absagen",
            appleProvider: FakeProvider(result: .success("Das Meeting morgen wurde abgesagt."), modelName: "Apple Foundation Models"),
            openAIProvider: FakeProvider(result: .success("x")) { openAICalled = true },
            groqProvider: FakeProvider(result: .success("y")) { groqCalled = true }
        )

        XCTAssertEqual(result.text, "Das Meeting morgen wurde abgesagt.")
        XCTAssertEqual(result.outcome, .local(model: "Apple Foundation Models"))
        XCTAssertFalse(openAICalled)
        XCTAssertFalse(groqCalled)
    }

    func testLokalWithNoAppleProviderFallsBackToRawTextSilently() async throws {
        var openAICalled = false
        var groqCalled = false

        let result = try await complete(
            makeRouter(backend: .lokal),
            text: "roher text",
            appleProvider: nil,
            openAIProvider: FakeProvider(result: .success("x")) { openAICalled = true },
            groqProvider: FakeProvider(result: .success("y")) { groqCalled = true }
        )

        XCTAssertEqual(result.text, "roher text")
        XCTAssertEqual(result.outcome, .localRewriteFailed)
        XCTAssertFalse(openAICalled)
        XCTAssertFalse(groqCalled)
    }

    func testLokalContextWindowExceededFallsBackToRawTextWithoutOnline() async throws {
        var openAICalled = false
        var groqCalled = false

        let result = try await complete(
            makeRouter(backend: .lokal),
            text: "roher text",
            appleProvider: FakeProvider(result: .failure(AppleRewriteError.contextWindowExceeded)),
            openAIProvider: FakeProvider(result: .success("x")) { openAICalled = true },
            groqProvider: FakeProvider(result: .success("y")) { groqCalled = true }
        )

        XCTAssertEqual(result.text, "roher text")
        XCTAssertEqual(result.outcome, .localRewriteFailed)
        XCTAssertFalse(openAICalled)
        XCTAssertFalse(groqCalled)
    }

    func testLokalGuardrailViolationFallsBackToRawTextWithoutOnline() async throws {
        var openAICalled = false
        var groqCalled = false

        let result = try await complete(
            makeRouter(backend: .lokal),
            text: "roher text",
            appleProvider: FakeProvider(result: .failure(AppleRewriteError.guardrailViolation)),
            openAIProvider: FakeProvider(result: .success("x")) { openAICalled = true },
            groqProvider: FakeProvider(result: .success("y")) { groqCalled = true }
        )

        XCTAssertEqual(result.text, "roher text")
        XCTAssertEqual(result.outcome, .localRewriteFailed)
        XCTAssertFalse(openAICalled)
        XCTAssertFalse(groqCalled)
    }

    func testLokalUnavailableErrorFallsBackToRawTextWithoutOnline() async throws {
        var openAICalled = false
        var groqCalled = false

        let result = try await complete(
            makeRouter(backend: .lokal),
            text: "roher text",
            appleProvider: FakeProvider(result: .failure(AppleRewriteError.unavailable)),
            openAIProvider: FakeProvider(result: .success("x")) { openAICalled = true },
            groqProvider: FakeProvider(result: .success("y")) { groqCalled = true }
        )

        XCTAssertEqual(result.text, "roher text")
        XCTAssertEqual(result.outcome, .localRewriteFailed)
        XCTAssertFalse(openAICalled)
        XCTAssertFalse(groqCalled)
    }

    func testLokalUnusableOutputFallsBackToRawTextWithoutOnline() async throws {
        let echoedPrompt = "Du bist ein Lektor. Verbessere den folgenden Text und gib nur das Ergebnis zurueck."
        var openAICalled = false
        var groqCalled = false

        let result = try await makeRouter(backend: .lokal).completeWithOutcome(
            text: "das meeting morgen absagen",
            systemPrompt: echoedPrompt,
            temperature: 0.3,
            appleProvider: FakeProvider(result: .success(echoedPrompt)),
            openAIProvider: FakeProvider(result: .success("x")) { openAICalled = true },
            groqProvider: FakeProvider(result: .success("y")) { groqCalled = true }
        )

        XCTAssertEqual(result.text, "das meeting morgen absagen")
        XCTAssertEqual(result.outcome, .localRewriteFailed)
        XCTAssertEqual(result.outcome.completionLabel, "Nachbearbeitung fehlgeschlagen – Rohtext eingefügt")
        XCTAssertFalse(openAICalled)
        XCTAssertFalse(groqCalled)
    }

    func testLokalSentinelOutputBypassesValidation() async throws {
        let result = try await complete(
            makeRouter(backend: .lokal),
            text: "ich habe gerade etwas gesagt",
            appleProvider: FakeProvider(result: .success(" KEINE_AUFNAHME_ERKANNT "), modelName: "Apple Foundation Models")
        )

        XCTAssertEqual(result.text, " KEINE_AUFNAHME_ERKANNT ")
        XCTAssertEqual(result.outcome, .local(model: "Apple Foundation Models"))
    }

    // MARK: - Online (out of scope, #198): minimal passthrough keeps the switch exhaustive

    func testOnlinePassesThroughToExistingGroqOpenAIRouting() async throws {
        let result = try await complete(
            makeRouter(backend: .online, providerMode: .groq, hasGroqKey: true),
            text: "hallo welt",
            appleProvider: nil,
            openAIProvider: FakeProvider(result: .success("OpenAI-Ergebnis"), modelName: "gpt-4o"),
            groqProvider: FakeProvider(result: .success("Groq-Ergebnis"), modelName: "openai/gpt-oss-120b")
        )

        XCTAssertEqual(result.text, "Groq-Ergebnis")
        XCTAssertEqual(result.outcome, .online(provider: .groq, model: "openai/gpt-oss-120b"))
    }

    // MARK: - Processing label (#128)

    func testProcessingLabelReportsLocalWhenAppleAvailable() {
        let label = RewriteRouter.processingLabel(appleProviderAvailable: true, providerMode: .groq, hasGroqKey: true)
        XCTAssertEqual(label, "Nachbearbeitung läuft – lokal auf diesem Mac")
    }

    func testProcessingLabelReportsOnlineProviderWhenAppleUnavailable() {
        let label = RewriteRouter.processingLabel(appleProviderAvailable: false, providerMode: .groq, hasGroqKey: true)
        XCTAssertEqual(label, "Nachbearbeitung läuft online mit Groq")
    }

    func testProcessingLabelReportsOpenAIWhenNoGroqKey() {
        let label = RewriteRouter.processingLabel(appleProviderAvailable: false, providerMode: .groq, hasGroqKey: false)
        XCTAssertEqual(label, "Nachbearbeitung läuft online mit OpenAI")
    }
}
