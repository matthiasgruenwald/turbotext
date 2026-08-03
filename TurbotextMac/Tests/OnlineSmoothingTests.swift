import XCTest
@testable import Turbotext

final class OnlineSmoothingTests: XCTestCase {

    private struct FakeProvider: LLMProvider {
        let result: Result<String, Error>
        var onCall: ((_ text: String, _ systemPrompt: String, _ temperature: Double) -> Void)?
        var modelName: String = "fake-model"

        func complete(text: String, systemPrompt: String, temperature: Double) async throws -> String {
            onCall?(text, systemPrompt, temperature)
            return try result.get()
        }
    }

    private func smooth(
        providerMode: RewriteProviderMode = .auto,
        hasGroqKey: Bool = true,
        openAI: FakeProvider,
        groq: FakeProvider,
        text: String = "roher satz"
    ) async -> String? {
        let smoothing = OnlineSmoothing(providerMode: providerMode, hasGroqKey: hasGroqKey)
        return await smoothing.smooth(text: text, openAIProvider: openAI, groqProvider: groq)
    }

    func testAutoWithGroqKeySmoothsViaGroq() async {
        var groqCalled = false
        var openAICalled = false

        let result = await smooth(
            openAI: FakeProvider(result: .success("openai")) { _, _, _ in openAICalled = true },
            groq: FakeProvider(result: .success("Geglättet.")) { _, _, _ in groqCalled = true }
        )

        XCTAssertEqual(result, "Geglättet.")
        XCTAssertTrue(groqCalled)
        XCTAssertFalse(openAICalled)
    }

    func testAutoFallsBackSilentlyToOpenAIWhenGroqFails() async {
        var openAICalled = false

        let result = await smooth(
            openAI: FakeProvider(result: .success("OpenAI-Ergebnis")) { _, _, _ in openAICalled = true },
            groq: FakeProvider(result: .failure(GroqLLMError.apiError("boom")))
        )

        XCTAssertEqual(result, "OpenAI-Ergebnis")
        XCTAssertTrue(openAICalled)
    }

    func testAllProvidersFailingReturnsNilForRawTextFallback() async {
        let result = await smooth(
            openAI: FakeProvider(result: .failure(LLMError.notConfigured)),
            groq: FakeProvider(result: .failure(GroqLLMError.networkError("offline")))
        )

        XCTAssertNil(result, "ohne Key, offline oder bei Anbieterfehlern scheitert die Online-Glättung still zu Rohtext")
    }

    func testNoGroqKeyGoesDirectlyToOpenAI() async {
        var groqCalled = false

        let result = await smooth(
            hasGroqKey: false,
            openAI: FakeProvider(result: .success("OpenAI-Ergebnis")),
            groq: FakeProvider(result: .success("Groq-Ergebnis")) { _, _, _ in groqCalled = true }
        )

        XCTAssertEqual(result, "OpenAI-Ergebnis")
        XCTAssertFalse(groqCalled)
    }

    func testImmerOpenAIRespectedEvenWithGroqKey() async {
        var groqCalled = false

        let result = await smooth(
            providerMode: .immerOpenAI,
            hasGroqKey: true,
            openAI: FakeProvider(result: .success("OpenAI-Ergebnis")),
            groq: FakeProvider(result: .success("Groq-Ergebnis")) { _, _, _ in groqCalled = true }
        )

        XCTAssertEqual(result, "OpenAI-Ergebnis")
        XCTAssertFalse(groqCalled)
    }

    func testWhitespaceOnlyResponseReturnsNil() async {
        let result = await smooth(
            openAI: FakeProvider(result: .success("   \n  ")),
            groq: FakeProvider(result: .failure(GroqLLMError.notConfigured))
        )

        XCTAssertNil(result, "eine leere Antwort erhält den Rohtext")
    }

    func testResponseIsTrimmed() async {
        let result = await smooth(
            openAI: FakeProvider(result: .success("  Geglättet.  \n")),
            groq: FakeProvider(result: .failure(GroqLLMError.notConfigured))
        )

        XCTAssertEqual(result, "Geglättet.")
    }

    func testUsesSharedSmoothingInstruction() async {
        var receivedPrompt: String?

        _ = await smooth(
            openAI: FakeProvider(result: .success("ok")) { _, systemPrompt, _ in receivedPrompt = systemPrompt },
            groq: FakeProvider(result: .failure(GroqLLMError.notConfigured))
        )

        XCTAssertEqual(receivedPrompt, SmoothingPrompt.systemInstruction)
    }

    func testPredictedProviderFollowsRewriteProviderSetting() {
        XCTAssertEqual(
            OnlineSmoothing(providerMode: .auto, hasGroqKey: true).predictedProvider, .groq,
            "Auto mit Groq-Key nennt Groq"
        )
        XCTAssertEqual(
            OnlineSmoothing(providerMode: .auto, hasGroqKey: false).predictedProvider, .openAI,
            "Auto ohne Groq-Key nennt OpenAI"
        )
        XCTAssertEqual(
            OnlineSmoothing(providerMode: .immerOpenAI, hasGroqKey: true).predictedProvider, .openAI,
            "'Immer OpenAI' gilt mit"
        )
    }
}
