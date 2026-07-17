import XCTest
import FoundationModels
@testable import Turbotext

// Note: deliberately no class-level `@available(macOS 26, *)`. XCTest instantiates test
// classes reflectively regardless of availability annotations, so gating happens per-test
// via a `guard #available` skip instead, keeping this safe to run (and cleanly skip) on
// older deployment targets.
final class AppleFoundationModelsProviderTests: XCTestCase {

    func testIsAvailableReflectsSystemLanguageModelAvailability() throws {
        guard #available(macOS 26, *) else {
            throw XCTSkip("Foundation Models erfordert macOS 26+.")
        }

        XCTAssertEqual(
            AppleFoundationModelsProvider.isAvailable,
            SystemLanguageModel.default.availability == .available
        )
    }

    func testCompleteRewritesShortTextWithTurbotextPlusSystemPrompt() async throws {
        guard #available(macOS 26, *) else {
            throw XCTSkip("Foundation Models erfordert macOS 26+.")
        }
        try XCTSkipUnless(
            AppleFoundationModelsProvider.isAvailable,
            "Apple Intelligence / Foundation Models nicht verfuegbar auf diesem Geraet."
        )

        let systemPrompt = TextImprovementSettings().systemPrompt
        let provider = AppleFoundationModelsProvider()

        let result = try await provider.complete(
            text: "das ist ein test satz mit ein paar fehler drin",
            systemPrompt: systemPrompt,
            temperature: 0.3
        )

        XCTAssertFalse(result.isEmpty)
    }

    func testCompleteThrowsUnavailableWhenModelIsNotAvailable() async throws {
        guard #available(macOS 26, *) else {
            throw XCTSkip("Foundation Models erfordert macOS 26+.")
        }
        try XCTSkipIf(
            AppleFoundationModelsProvider.isAvailable,
            "Test setzt ein nicht verfuegbares Modell voraus."
        )

        let provider = AppleFoundationModelsProvider()

        do {
            _ = try await provider.complete(text: "hallo", systemPrompt: "system", temperature: 0.3)
            XCTFail("Expected AppleRewriteError.unavailable")
        } catch AppleRewriteError.unavailable {
            // expected
        } catch {
            XCTFail("Expected AppleRewriteError.unavailable, got \(error)")
        }
    }
}
