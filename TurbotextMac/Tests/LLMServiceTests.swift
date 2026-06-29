import XCTest
@testable import Turbotext

@MainActor
final class LLMServiceTests: XCTestCase {

    override func tearDown() {
        KeychainService.delete(key: .openAIAPIKey)
        KeychainService.delete(key: .groqAPIKey)
        restoreDefaultSeam()
        super.tearDown()
    }

    private func restoreDefaultSeam() {
        LLMService.providerComplete = { text, systemPrompt, model, temperature in
            try await LLMServiceTests.defaultOpenAIComplete(
                text: text,
                systemPrompt: systemPrompt,
                model: model,
                temperature: temperature
            )
        }
        LLMService.groqComplete = { text, systemPrompt, temperature in
            try await GroqLLMService.complete(text: text, systemPrompt: systemPrompt, temperature: temperature)
        }
        LLMService.providerMode = { .auto }
        LLMService.hasGroqKey = {
            KeychainService.load(key: .groqAPIKey) != nil
        }
    }

    /// Reimplements the production default behaviour so we can restore it after
    /// swapping the seam, without exposing the private original.
    private static func defaultOpenAIComplete(
        text: String,
        systemPrompt: String,
        model: RewriteModel,
        temperature: Double
    ) async throws -> String {
        guard KeychainService.load(key: .openAIAPIKey) != nil else {
            throw LLMError.notConfigured
        }
        return "unused-in-tests"
    }

    func testSeamCanBeSwappedAndReceivesExpectedParameters() async throws {
        var capturedText: String?
        var capturedSystemPrompt: String?
        var capturedModel: RewriteModel?
        var capturedTemperature: Double?

        LLMService.providerComplete = { text, systemPrompt, model, temperature in
            capturedText = text
            capturedSystemPrompt = systemPrompt
            capturedModel = model
            capturedTemperature = temperature
            return "Verbesserter Text"
        }

        let settings = TextImprovementSettings()

        let result = try await LLMService.improve(text: "hallo welt", settings: settings)

        XCTAssertEqual(result, "Verbesserter Text")
        XCTAssertEqual(capturedText, "hallo welt")
        XCTAssertEqual(capturedModel, .fastEdit)
        XCTAssertEqual(capturedTemperature, 0.3)
        XCTAssertNotNil(capturedSystemPrompt)
    }

    func testDefaultSeamThrowsNotConfiguredWithoutAPIKey() async {
        KeychainService.delete(key: .openAIAPIKey)
        let settings = TextImprovementSettings()

        do {
            _ = try await LLMService.improve(text: "hallo welt", settings: settings)
            XCTFail("Expected LLMError.notConfigured")
        } catch LLMError.notConfigured {
            // expected
        } catch {
            XCTFail("Expected LLMError.notConfigured, got \(error)")
        }
    }

    // MARK: - Groq fallback (#54)

    func testAutoModeWithGroqKeyUsesGroqOnSuccess() async throws {
        LLMService.providerMode = { .auto }
        LLMService.hasGroqKey = { true }

        var groqCalled = false
        var openAICalled = false

        LLMService.groqComplete = { _, _, _ in
            groqCalled = true
            return "Groq-Ergebnis"
        }
        LLMService.providerComplete = { _, _, _, _ in
            openAICalled = true
            return "OpenAI-Ergebnis"
        }

        let settings = TextImprovementSettings()
        let result = try await LLMService.improve(text: "hallo welt", settings: settings)

        XCTAssertEqual(result, "Groq-Ergebnis")
        XCTAssertTrue(groqCalled)
        XCTAssertFalse(openAICalled)
    }

    func testAutoModeFallsBackToOpenAIWhenGroqFails() async throws {
        LLMService.providerMode = { .auto }
        LLMService.hasGroqKey = { true }

        var openAICalled = false

        LLMService.groqComplete = { _, _, _ in
            throw GroqLLMError.apiError("boom")
        }
        LLMService.providerComplete = { _, _, _, _ in
            openAICalled = true
            return "OpenAI-Ergebnis"
        }

        let settings = TextImprovementSettings()
        let result = try await LLMService.improve(text: "hallo welt", settings: settings)

        XCTAssertEqual(result, "OpenAI-Ergebnis")
        XCTAssertTrue(openAICalled)
    }

    func testNoGroqKeyGoesDirectlyToOpenAI() async throws {
        LLMService.providerMode = { .auto }
        LLMService.hasGroqKey = { false }

        var groqCalled = false

        LLMService.groqComplete = { _, _, _ in
            groqCalled = true
            return "Groq-Ergebnis"
        }
        LLMService.providerComplete = { _, _, _, _ in
            "OpenAI-Ergebnis"
        }

        let settings = TextImprovementSettings()
        let result = try await LLMService.improve(text: "hallo welt", settings: settings)

        XCTAssertEqual(result, "OpenAI-Ergebnis")
        XCTAssertFalse(groqCalled)
    }

    func testImmerOpenAIModeIgnoresGroqEvenWithKey() async throws {
        LLMService.providerMode = { .immerOpenAI }
        LLMService.hasGroqKey = { true }

        var groqCalled = false

        LLMService.groqComplete = { _, _, _ in
            groqCalled = true
            return "Groq-Ergebnis"
        }
        LLMService.providerComplete = { _, _, _, _ in
            "OpenAI-Ergebnis"
        }

        let settings = TextImprovementSettings()
        let result = try await LLMService.improve(text: "hallo welt", settings: settings)

        XCTAssertEqual(result, "OpenAI-Ergebnis")
        XCTAssertFalse(groqCalled)
    }
}
