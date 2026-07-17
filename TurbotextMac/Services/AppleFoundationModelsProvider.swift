import Foundation
import FoundationModels

/// Errors surfaced by ``AppleFoundationModelsProvider``, mapped from the underlying
/// `LanguageModelSession.GenerationError` cases we care about.
enum AppleRewriteError: LocalizedError {
    case unavailable
    case contextWindowExceeded
    case guardrailViolation

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Geraeteinterne Textverbesserung ist auf diesem Geraet nicht verfuegbar."
        case .contextWindowExceeded:
            return "Der Text ist zu lang fuer die geraeteinterne Verarbeitung."
        case .guardrailViolation:
            return "Der Text konnte aus Sicherheitsgruenden nicht geraeteintern verarbeitet werden."
        }
    }
}

/// On-device rewrite provider backed by Apple's Foundation Models framework.
/// Requires macOS 26+ and Apple Silicon (enforced transitively via `SystemLanguageModel.availability`).
@available(macOS 26, *)
struct AppleFoundationModelsProvider: LLMProvider {
    static var isAvailable: Bool {
        SystemLanguageModel.default.availability == .available
    }

    func complete(text: String, systemPrompt: String, temperature: Double) async throws -> String {
        guard Self.isAvailable else {
            throw AppleRewriteError.unavailable
        }

        let session = LanguageModelSession(instructions: systemPrompt)
        do {
            let response = try await session.respond(
                to: text,
                options: GenerationOptions(temperature: temperature)
            )
            return response.content
        } catch LanguageModelSession.GenerationError.exceededContextWindowSize {
            throw AppleRewriteError.contextWindowExceeded
        } catch LanguageModelSession.GenerationError.guardrailViolation {
            throw AppleRewriteError.guardrailViolation
        }
    }
}
