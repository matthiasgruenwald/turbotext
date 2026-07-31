import Foundation

enum LocalRewriteAvailability: Equatable {
    case available
    case requiresNewerMacOS
    case appleIntelligenceNotEnabled

    static var current: LocalRewriteAvailability {
        guard #available(macOS 26, *) else { return .requiresNewerMacOS }
        guard AppleFoundationModelsProvider.isAvailable else { return .appleIntelligenceNotEnabled }
        return .available
    }

    var isAvailable: Bool { self == .available }

    var statusLabel: String {
        isAvailable ? "Lokale Textverbesserung verfügbar" : "Lokale Textverbesserung nicht verfügbar"
    }

    var statusIconName: String {
        isAvailable ? "checkmark.circle.fill" : "xmark.circle.fill"
    }

    var detailText: String {
        switch self {
        case .available:
            return "Textverbesserung, Dampf ablassen und Emoji-Text laufen zuerst lokal auf diesem Mac. Nur bei lokalen Fehlern fragt Turbotext um Erlaubnis für den Online-Fallback."
        case .requiresNewerMacOS:
            return "Erfordert macOS 26 oder neuer. Textverbesserung läuft über Groq oder OpenAI."
        case .appleIntelligenceNotEnabled:
            return "Apple Intelligence ist auf diesem Mac nicht aktiviert. Textverbesserung läuft über Groq oder OpenAI."
        }
    }
}
