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

    private final class ConsentSpy {
        var calls: [(reason: RewriteConsentReason, provider: OnlineProvider)] = []
        var decision: RewriteRouter.ConsentDecision = .insertRawText

        func present(reason: RewriteConsentReason, provider: OnlineProvider) async -> RewriteRouter.ConsentDecision {
            calls.append((reason, provider))
            return decision
        }
    }

    private final class ConsentStore {
        var consents: [WorkflowType: OnlineProvider] = [:]

        func read(_ workflow: WorkflowType) -> OnlineProvider? { consents[workflow] }
        func write(_ workflow: WorkflowType, _ provider: OnlineProvider?) { consents[workflow] = provider }
    }

    private func makeRouter(providerMode: RewriteProviderMode = .auto, hasGroqKey: Bool = true) -> RewriteRouter {
        RewriteRouter(providerMode: providerMode, hasGroqKey: hasGroqKey)
    }

    // MARK: - Apple unavailable -> unchanged ProviderRouter

    func testAppleProviderNilFallsBackToExistingProviderRouterUnchanged() async throws {
        var groqCalled = false
        let consentSpy = ConsentSpy()
        let store = ConsentStore()

        let result = try await makeRouter().complete(
            text: "hallo welt",
            systemPrompt: "system",
            temperature: 0.3,
            workflow: .textImprover,
            appleProvider: nil,
            openAIProvider: FakeProvider(result: .success("OpenAI-Ergebnis")),
            groqProvider: FakeProvider(result: .success("Groq-Ergebnis")) { groqCalled = true },
            presentConsent: consentSpy.present,
            readConsent: store.read,
            writeConsent: store.write
        )

        XCTAssertEqual(result, "Groq-Ergebnis")
        XCTAssertTrue(groqCalled)
        XCTAssertTrue(consentSpy.calls.isEmpty)
    }

    // MARK: - Apple available and succeeds

    func testAppleProviderSuccessSkipsOnlineEntirely() async throws {
        let consentSpy = ConsentSpy()
        let store = ConsentStore()

        let result = try await makeRouter().complete(
            text: "hallo welt",
            systemPrompt: "system",
            temperature: 0.3,
            workflow: .textImprover,
            appleProvider: FakeProvider(result: .success("Lokal-Ergebnis")),
            openAIProvider: FakeProvider(result: .success("OpenAI-Ergebnis")),
            groqProvider: FakeProvider(result: .success("Groq-Ergebnis")),
            presentConsent: consentSpy.present,
            readConsent: store.read,
            writeConsent: store.write
        )

        XCTAssertEqual(result, "Lokal-Ergebnis")
        XCTAssertTrue(consentSpy.calls.isEmpty)
    }

    // MARK: - Apple .unavailable at call time -> fall back silently, no dialog

    func testAppleUnavailableErrorFallsBackWithoutDialog() async throws {
        var openAICalled = false
        let consentSpy = ConsentSpy()
        let store = ConsentStore()

        let result = try await makeRouter(providerMode: .immerOpenAI).complete(
            text: "hallo welt",
            systemPrompt: "system",
            temperature: 0.3,
            workflow: .textImprover,
            appleProvider: FakeProvider(result: .failure(AppleRewriteError.unavailable)),
            openAIProvider: FakeProvider(result: .success("OpenAI-Ergebnis")) { openAICalled = true },
            groqProvider: FakeProvider(result: .success("Groq-Ergebnis")),
            presentConsent: consentSpy.present,
            readConsent: store.read,
            writeConsent: store.write
        )

        XCTAssertEqual(result, "OpenAI-Ergebnis")
        XCTAssertTrue(openAICalled)
        XCTAssertTrue(consentSpy.calls.isEmpty)
    }

    // MARK: - Context window exceeded -> dialog, names concrete provider

    func testContextWindowExceededPresentsDialogNamingGroqInAutoMode() async throws {
        let consentSpy = ConsentSpy()
        consentSpy.decision = .insertRawText
        let store = ConsentStore()

        _ = try await makeRouter(providerMode: .auto, hasGroqKey: true).complete(
            text: "roher text",
            systemPrompt: "system",
            temperature: 0.3,
            workflow: .textImprover,
            appleProvider: FakeProvider(result: .failure(AppleRewriteError.contextWindowExceeded)),
            openAIProvider: FakeProvider(result: .success("OpenAI-Ergebnis")),
            groqProvider: FakeProvider(result: .success("Groq-Ergebnis")),
            presentConsent: consentSpy.present,
            readConsent: store.read,
            writeConsent: store.write
        )

        XCTAssertEqual(consentSpy.calls.count, 1)
        XCTAssertEqual(consentSpy.calls.first?.provider, .groq)
        XCTAssertEqual(consentSpy.calls.first?.reason, .contextWindowExceeded)
    }

    func testGuardrailViolationPresentsDialogNamingOpenAIWhenNoGroqKey() async throws {
        let consentSpy = ConsentSpy()
        consentSpy.decision = .insertRawText
        let store = ConsentStore()

        _ = try await makeRouter(providerMode: .auto, hasGroqKey: false).complete(
            text: "roher text",
            systemPrompt: "system",
            temperature: 0.3,
            workflow: .textImprover,
            appleProvider: FakeProvider(result: .failure(AppleRewriteError.guardrailViolation)),
            openAIProvider: FakeProvider(result: .success("OpenAI-Ergebnis")),
            groqProvider: FakeProvider(result: .success("Groq-Ergebnis")),
            presentConsent: consentSpy.present,
            readConsent: store.read,
            writeConsent: store.write
        )

        XCTAssertEqual(consentSpy.calls.count, 1)
        XCTAssertEqual(consentSpy.calls.first?.provider, .openAI)
        XCTAssertEqual(consentSpy.calls.first?.reason, .guardrailViolation)
    }

    // MARK: - Raw text path: reject or dismiss without action

    func testInsertRawTextDecisionReturnsUnmodifiedRawText() async throws {
        let consentSpy = ConsentSpy()
        consentSpy.decision = .insertRawText
        let store = ConsentStore()
        var openAICalled = false
        var groqCalled = false

        let result = try await makeRouter().complete(
            text: "roher text unveraendert",
            systemPrompt: "system",
            temperature: 0.3,
            workflow: .textImprover,
            appleProvider: FakeProvider(result: .failure(AppleRewriteError.contextWindowExceeded)),
            openAIProvider: FakeProvider(result: .success("OpenAI-Ergebnis")) { openAICalled = true },
            groqProvider: FakeProvider(result: .success("Groq-Ergebnis")) { groqCalled = true },
            presentConsent: consentSpy.present,
            readConsent: store.read,
            writeConsent: store.write
        )

        XCTAssertEqual(result, "roher text unveraendert")
        XCTAssertFalse(openAICalled)
        XCTAssertFalse(groqCalled)
    }

    // MARK: - Consent granted, remembered -> persisted and skips dialog next run

    func testConsentGrantedWithRememberPersistsAndSkipsDialogOnNextRun() async throws {
        let consentSpy = ConsentSpy()
        consentSpy.decision = .continueOnline(remember: true)
        let store = ConsentStore()

        let first = try await makeRouter(providerMode: .immerOpenAI).complete(
            text: "roher text",
            systemPrompt: "system",
            temperature: 0.3,
            workflow: .textImprover,
            appleProvider: FakeProvider(result: .failure(AppleRewriteError.contextWindowExceeded)),
            openAIProvider: FakeProvider(result: .success("OpenAI-Ergebnis")),
            groqProvider: FakeProvider(result: .success("Groq-Ergebnis")),
            presentConsent: consentSpy.present,
            readConsent: store.read,
            writeConsent: store.write
        )
        XCTAssertEqual(first, "OpenAI-Ergebnis")
        XCTAssertEqual(store.consents[.textImprover], .openAI)
        XCTAssertEqual(consentSpy.calls.count, 1)

        let second = try await makeRouter(providerMode: .immerOpenAI).complete(
            text: "roher text 2",
            systemPrompt: "system",
            temperature: 0.3,
            workflow: .textImprover,
            appleProvider: FakeProvider(result: .failure(AppleRewriteError.contextWindowExceeded)),
            openAIProvider: FakeProvider(result: .success("OpenAI-Ergebnis-2")),
            groqProvider: FakeProvider(result: .success("Groq-Ergebnis")),
            presentConsent: consentSpy.present,
            readConsent: store.read,
            writeConsent: store.write
        )

        XCTAssertEqual(second, "OpenAI-Ergebnis-2")
        // Dialog was not shown again for the second run.
        XCTAssertEqual(consentSpy.calls.count, 1)
    }

    // MARK: - Provider switch invalidates stored consent

    func testProviderSwitchDiscardsStoredConsentAndAsksAgain() async throws {
        let consentSpy = ConsentSpy()
        consentSpy.decision = .insertRawText
        let store = ConsentStore()
        store.consents[.textImprover] = .openAI // stale: was consented to OpenAI

        // Now configured for Auto+Groq, so the stored OpenAI consent no longer matches.
        _ = try await makeRouter(providerMode: .auto, hasGroqKey: true).complete(
            text: "roher text",
            systemPrompt: "system",
            temperature: 0.3,
            workflow: .textImprover,
            appleProvider: FakeProvider(result: .failure(AppleRewriteError.contextWindowExceeded)),
            openAIProvider: FakeProvider(result: .success("OpenAI-Ergebnis")),
            groqProvider: FakeProvider(result: .success("Groq-Ergebnis")),
            presentConsent: consentSpy.present,
            readConsent: store.read,
            writeConsent: store.write
        )

        XCTAssertNil(store.consents[.textImprover])
        XCTAssertEqual(consentSpy.calls.count, 1)
        XCTAssertEqual(consentSpy.calls.first?.provider, .groq)
    }

    // MARK: - No silent fallback: Groq failing after consent re-prompts with OpenAI

    func testGroqFailureAfterConsentReAsksWithOpenAIInsteadOfSilentFallback() async throws {
        let consentSpy = ConsentSpy()
        consentSpy.decision = .continueOnline(remember: false)
        let store = ConsentStore()

        let result = try await makeRouter(providerMode: .auto, hasGroqKey: true).complete(
            text: "roher text",
            systemPrompt: "system",
            temperature: 0.3,
            workflow: .textImprover,
            appleProvider: FakeProvider(result: .failure(AppleRewriteError.contextWindowExceeded)),
            openAIProvider: FakeProvider(result: .success("OpenAI-Ergebnis")),
            groqProvider: FakeProvider(result: .failure(GroqLLMError.apiError("boom"))),
            presentConsent: consentSpy.present,
            readConsent: store.read,
            writeConsent: store.write
        )

        XCTAssertEqual(result, "OpenAI-Ergebnis")
        XCTAssertEqual(consentSpy.calls.count, 2)
        XCTAssertEqual(consentSpy.calls[0].provider, .groq)
        XCTAssertEqual(consentSpy.calls[1].provider, .openAI)
    }

    func testDismissedDialogInsertsRawTextSameAsReject() async throws {
        let consentSpy = ConsentSpy()
        consentSpy.decision = .insertRawText // dismissal maps to the same decision as "reject"
        let store = ConsentStore()

        let result = try await makeRouter().complete(
            text: "unveraendert",
            systemPrompt: "system",
            temperature: 0.3,
            workflow: .dampfAblassen,
            appleProvider: FakeProvider(result: .failure(AppleRewriteError.guardrailViolation)),
            openAIProvider: FakeProvider(result: .success("x")),
            groqProvider: FakeProvider(result: .success("y")),
            presentConsent: consentSpy.present,
            readConsent: store.read,
            writeConsent: store.write
        )

        XCTAssertEqual(result, "unveraendert")
        XCTAssertNil(store.consents[.dampfAblassen])
    }

    // MARK: - Outcome / completion label (#128)

    func testCompleteWithOutcomeReportsLocalOnAppleSuccess() async throws {
        let consentSpy = ConsentSpy()
        let store = ConsentStore()

        let result = try await makeRouter().completeWithOutcome(
            text: "hallo welt",
            systemPrompt: "system",
            temperature: 0.3,
            workflow: .textImprover,
            appleProvider: FakeProvider(result: .success("Lokal-Ergebnis"), modelName: "Apple Foundation Models"),
            openAIProvider: FakeProvider(result: .success("OpenAI-Ergebnis")),
            groqProvider: FakeProvider(result: .success("Groq-Ergebnis")),
            presentConsent: consentSpy.present,
            readConsent: store.read,
            writeConsent: store.write
        )

        XCTAssertEqual(result.text, "Lokal-Ergebnis")
        XCTAssertEqual(result.outcome, .local(model: "Apple Foundation Models"))
        XCTAssertEqual(result.outcome.completionLabel, "Text lokal verbessert · Apple Foundation Models")
    }

    func testCompleteWithOutcomeReportsOnlineProviderAndModelWhenAppleUnavailable() async throws {
        let consentSpy = ConsentSpy()
        let store = ConsentStore()

        let result = try await makeRouter(providerMode: .auto, hasGroqKey: true).completeWithOutcome(
            text: "hallo welt",
            systemPrompt: "system",
            temperature: 0.3,
            workflow: .textImprover,
            appleProvider: nil,
            openAIProvider: FakeProvider(result: .success("OpenAI-Ergebnis"), modelName: "gpt-4o"),
            groqProvider: FakeProvider(result: .success("Groq-Ergebnis"), modelName: "openai/gpt-oss-120b"),
            presentConsent: consentSpy.present,
            readConsent: store.read,
            writeConsent: store.write
        )

        XCTAssertEqual(result.outcome, .online(provider: .groq, model: "openai/gpt-oss-120b"))
        XCTAssertEqual(result.outcome.completionLabel, "Text online verbessert · Groq · openai/gpt-oss-120b")
    }

    func testCompleteWithOutcomeReportsRawTextInsertedWithNoCompletionLabel() async throws {
        let consentSpy = ConsentSpy()
        consentSpy.decision = .insertRawText
        let store = ConsentStore()

        let result = try await makeRouter().completeWithOutcome(
            text: "roher text",
            systemPrompt: "system",
            temperature: 0.3,
            workflow: .textImprover,
            appleProvider: FakeProvider(result: .failure(AppleRewriteError.contextWindowExceeded)),
            openAIProvider: FakeProvider(result: .success("OpenAI-Ergebnis")),
            groqProvider: FakeProvider(result: .success("Groq-Ergebnis")),
            presentConsent: consentSpy.present,
            readConsent: store.read,
            writeConsent: store.write
        )

        XCTAssertEqual(result.outcome, .rawTextInserted)
        XCTAssertNil(result.outcome.completionLabel)
    }

    // MARK: - Processing label (#128)

    func testProcessingLabelReportsLocalWhenAppleAvailable() {
        let label = RewriteRouter.processingLabel(appleProviderAvailable: true, providerMode: .auto, hasGroqKey: true)
        XCTAssertEqual(label, "Nachbearbeitung läuft – lokal auf diesem Mac")
    }

    func testProcessingLabelReportsOnlineProviderWhenAppleUnavailable() {
        let label = RewriteRouter.processingLabel(appleProviderAvailable: false, providerMode: .auto, hasGroqKey: true)
        XCTAssertEqual(label, "Nachbearbeitung läuft online mit Groq")
    }

    func testProcessingLabelReportsOpenAIWhenNoGroqKey() {
        let label = RewriteRouter.processingLabel(appleProviderAvailable: false, providerMode: .auto, hasGroqKey: false)
        XCTAssertEqual(label, "Nachbearbeitung läuft online mit OpenAI")
    }
}
