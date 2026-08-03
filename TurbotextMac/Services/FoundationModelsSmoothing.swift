import Foundation
import FoundationModels
import OSLog

private let smoothingLogger = Logger(subsystem: "app.turbotext.mac", category: "LiveDictation")

@available(macOS 26, *)
struct FoundationModelsSmoothing {
    static var isAvailable: Bool {
        SystemLanguageModel.default.availability == .available
    }

    func smooth(text: String) async -> String? {
        guard Self.isAvailable else { return nil }
        let started = ContinuousClock.now
        let result: String?
        do {
            let content = try await respond(to: text)
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            result = trimmed.isEmpty ? nil : trimmed
        } catch {
            result = nil
        }
        logPass(chars: text.count, since: started, smoothed: result != nil)
        return result
    }

    // A stuck on-device session would otherwise block the transcript indefinitely;
    // the race caps latency and degrades to the raw text via the nil path.
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

    // Real-dictation latency data decides whether the smoothing budget (#163)
    // is ever won on this hardware; without this line the question is unanswerable.
    private func logPass(chars: Int, since started: ContinuousClock.Instant, smoothed: Bool) {
        let elapsed = started.duration(to: .now)
        let seconds = Double(elapsed.components.seconds)
            + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000_000
        smoothingLogger.info(
            "smoothing pass chars=\(chars) latency=\(String(format: "%.1f", seconds), privacy: .public)s smoothed=\(smoothed) cancelled=\(Task.isCancelled)"
        )
    }

    private static let systemInstruction = """
        Du glaettest ein Diktat: korrigiere Satzzeichen, Gross-/Kleinschreibung und \
        offensichtliche Erkennungsfehler. Behalte Bedeutung und Wortlaut moeglichst bei. \
        Gib NUR den geglaetteten Text zurueck, keine Erklaerungen.
        """
}
