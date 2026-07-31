import Foundation
import FoundationModels

@available(macOS 26, *)
struct FoundationModelsSmoothing: LiveSmoothing {
    static var isAvailable: Bool {
        SystemLanguageModel.default.availability == .available
    }

    func smooth(segment: String, context: String?) async -> String? {
        guard Self.isAvailable else { return nil }
        do {
            let content = try await respond(to: Self.message(segment: segment, context: context))
            let result = content.trimmingCharacters(in: .whitespacesAndNewlines)
            return result.isEmpty ? nil : result
        } catch {
            return nil
        }
    }

    // A stuck on-device session would otherwise block the live transcript indefinitely;
    // the race caps latency and degrades to the raw segment via the nil path.
    private func respond(to message: String) async throws -> String {
        try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                let session = LanguageModelSession(instructions: Self.systemInstruction)
                let response = try await session.respond(to: message, options: GenerationOptions(temperature: 0.1))
                return response.content
            }
            group.addTask {
                try await Task.sleep(for: .seconds(30))
                throw CancellationError()
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw CancellationError() }
            return first
        }
    }

    private static let systemInstruction = """
        Du glaettest ein Diktat-Segment: korrigiere Satzzeichen, Gross-/Kleinschreibung und \
        offensichtliche Erkennungsfehler. Behalte Bedeutung und Wortlaut moeglichst bei. \
        Gib NUR den geglaetteten Text zurueck, keine Erklaerungen.
        """

    private static func message(segment: String, context: String?) -> String {
        guard let context, !context.isEmpty else { return segment }
        return "Vorheriger Kontext (endet hier): \(context)\n\nSegment: \(segment)"
    }
}
