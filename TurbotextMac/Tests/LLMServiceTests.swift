import XCTest
@testable import Turbotext

@MainActor
final class LLMServiceTests: XCTestCase {

    override func tearDown() {
        KeychainService.delete(key: .openAIAPIKey)
        KeychainService.delete(key: .groqAPIKey)
        super.tearDown()
    }

    private struct FakeProvider: LLMProvider {
        let result: Result<String, Error>
        var onCalled: (() -> Void)?

        func complete(text: String, systemPrompt: String, temperature: Double) async throws -> String {
            onCalled?()
            return try result.get()
        }
    }

    // MARK: - ProviderRouter routing (#54 behaviour, now exercised via explicit DI)

    func testAutoModeWithGroqKeyUsesGroqOnSuccess() async throws {
        var groqCalled = false
        var openAICalled = false

        let router = ProviderRouter(providerMode: .auto, hasGroqKey: true)
        let result = try await router.complete(
            text: "hallo welt",
            systemPrompt: "system",
            temperature: 0.3,
            openAIProvider: FakeProvider(result: .success("OpenAI-Ergebnis")) { openAICalled = true },
            groqProvider: FakeProvider(result: .success("Groq-Ergebnis")) { groqCalled = true }
        )

        XCTAssertEqual(result, "Groq-Ergebnis")
        XCTAssertTrue(groqCalled)
        XCTAssertFalse(openAICalled)
    }

    func testAutoModeFallsBackToOpenAIWhenGroqFails() async throws {
        var openAICalled = false

        let router = ProviderRouter(providerMode: .auto, hasGroqKey: true)
        let result = try await router.complete(
            text: "hallo welt",
            systemPrompt: "system",
            temperature: 0.3,
            openAIProvider: FakeProvider(result: .success("OpenAI-Ergebnis")) { openAICalled = true },
            groqProvider: FakeProvider(result: .failure(GroqLLMError.apiError("boom")))
        )

        XCTAssertEqual(result, "OpenAI-Ergebnis")
        XCTAssertTrue(openAICalled)
    }

    func testNoGroqKeyGoesDirectlyToOpenAI() async throws {
        var groqCalled = false

        let router = ProviderRouter(providerMode: .auto, hasGroqKey: false)
        let result = try await router.complete(
            text: "hallo welt",
            systemPrompt: "system",
            temperature: 0.3,
            openAIProvider: FakeProvider(result: .success("OpenAI-Ergebnis")),
            groqProvider: FakeProvider(result: .success("Groq-Ergebnis")) { groqCalled = true }
        )

        XCTAssertEqual(result, "OpenAI-Ergebnis")
        XCTAssertFalse(groqCalled)
    }

    func testImmerOpenAIModeIgnoresGroqEvenWithKey() async throws {
        var groqCalled = false

        let router = ProviderRouter(providerMode: .immerOpenAI, hasGroqKey: true)
        let result = try await router.complete(
            text: "hallo welt",
            systemPrompt: "system",
            temperature: 0.3,
            openAIProvider: FakeProvider(result: .success("OpenAI-Ergebnis")),
            groqProvider: FakeProvider(result: .success("Groq-Ergebnis")) { groqCalled = true }
        )

        XCTAssertEqual(result, "OpenAI-Ergebnis")
        XCTAssertFalse(groqCalled)
    }

    // MARK: - LLMService call-site integration

    func testDefaultSeamThrowsNotConfiguredWithoutAPIKey() async {
        KeychainService.delete(key: .openAIAPIKey)
        KeychainService.delete(key: .groqAPIKey)
        let settings = TextImprovementSettings()

        do {
            _ = try await LLMService.improve(text: "hallo welt", settings: settings, providerMode: .immerOpenAI)
            XCTFail("Expected LLMError.notConfigured")
        } catch LLMError.notConfigured {
            // expected
        } catch {
            XCTFail("Expected LLMError.notConfigured, got \(error)")
        }
    }

    func testImproveWithoutGroqKeyUsesOpenAIPath() async {
        KeychainService.delete(key: .openAIAPIKey)
        KeychainService.delete(key: .groqAPIKey)
        let settings = TextImprovementSettings()

        do {
            _ = try await LLMService.improve(
                text: "hallo welt",
                settings: settings,
                providerMode: .auto,
                hasGroqKey: false
            )
            XCTFail("Expected LLMError.notConfigured")
        } catch LLMError.notConfigured {
            // expected: no Groq key and no OpenAI key means OpenAI path is hit directly
        } catch {
            XCTFail("Expected LLMError.notConfigured, got \(error)")
        }
    }
}
