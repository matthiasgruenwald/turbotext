import XCTest
@testable import Turbotext

@MainActor
final class LLMServiceTests: XCTestCase {

    override func tearDown() {
        KeychainService.delete(key: .openAIAPIKey)
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
}
