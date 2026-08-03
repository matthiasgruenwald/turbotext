import Foundation
import FoundationModels
import OSLog

private let smoothingLogger = Logger(subsystem: "app.turbotext.mac", category: "LiveDictation")

/// Why the on-device smoothing backend is (not) usable, shown in the settings when
/// "Auf diesem Mac" is selected (#170). Follows the `LocalRewriteAvailability` pattern
/// but keeps the SDK's distinct reasons instead of collapsing them into a Bool.
enum OnDeviceSmoothingAvailability: Equatable {
    case available
    case requiresNewerMacOS
    case deviceNotEligible
    case appleIntelligenceNotEnabled
    case modelNotReady
    case germanLanguageDataMissing
    case unavailableUnknown

    static var current: OnDeviceSmoothingAvailability {
        guard #available(macOS 26, *) else { return .requiresNewerMacOS }
        let model = SystemLanguageModel.default
        let supportsGerman = model.availability == .available
            && model.supportedLanguages.contains { $0.languageCode?.identifier == "de" }
        return resolve(systemAvailability: model.availability, supportsGerman: supportsGerman)
    }

    @available(macOS 26, *)
    static func resolve(
        systemAvailability: SystemLanguageModel.Availability,
        supportsGerman: Bool
    ) -> OnDeviceSmoothingAvailability {
        switch systemAvailability {
        case .available:
            return supportsGerman ? .available : .germanLanguageDataMissing
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible: return .deviceNotEligible
            case .appleIntelligenceNotEnabled: return .appleIntelligenceNotEnabled
            case .modelNotReady: return .modelNotReady
            @unknown default: return .unavailableUnknown
            }
        }
    }

    var isAvailable: Bool { self == .available }

    var reasonText: String? {
        switch self {
        case .available:
            return nil
        case .requiresNewerMacOS:
            return "Erfordert macOS 26 oder neuer."
        case .deviceNotEligible:
            return "Dieser Mac unterstützt Apple Intelligence nicht."
        case .appleIntelligenceNotEnabled:
            return "Apple Intelligence ist auf diesem Mac nicht aktiviert."
        case .modelNotReady:
            return "Das geräteinterne Sprachmodell ist noch nicht bereit – fehlen die deutschen Sprachdaten, lassen sie sich in den Systemeinstellungen unter Apple Intelligence laden."
        case .germanLanguageDataMissing:
            return "Die deutschen Sprachdaten sind auf diesem Mac nicht installiert."
        case .unavailableUnknown:
            return "Das geräteinterne Sprachmodell ist auf diesem Mac derzeit nicht verfügbar."
        }
    }
}

@available(macOS 26, *)
struct FoundationModelsSmoothing {
    static var isAvailable: Bool {
        OnDeviceSmoothingAvailability.current.isAvailable
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
                let session = LanguageModelSession(instructions: SmoothingPrompt.systemInstruction)
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
}
