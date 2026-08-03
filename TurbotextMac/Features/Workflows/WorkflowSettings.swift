import Foundation

// MARK: - App Settings

struct AppSettings: Codable, Equatable {
    var hotkeyMode: HotkeyMode = .hold
    var hasSeenOnboarding: Bool = false
    var alwaysLocalTranscription: Bool = false
    var selectedLocalTranscriptionModelName: String = LocalTranscriptionService.recommendedFastModelName
    var selectedLocalTranscriptionBackend: LocalTranscriptionBackend = .appleSpeech
    var hasAutoSelectedFastLocalModel: Bool = false
    var hasDismissedInputMonitoringHint: Bool = false
    var dockModeEnabled: Bool = true
    var autoFallbackToLocalOnOffline: Bool = false
    var rewritingProviderMode: RewriteProviderMode = .auto
    var recordingOverlayMode: RecordingOverlayMode = .screenBottomCenter
    /// Per-workflow consent to route rewrites to a named online provider once on-device
    /// rewriting fails (#124). Cleared for a workflow whenever its configured online
    /// provider changes, so a fresh consent is required.
    var rewriteConsents: [WorkflowType: OnlineProvider] = [:]
    /// Permanently hides the ~3s post-insert rewrite completion label in the signal pill
    /// (#128), e.g. after the user dismisses it once from the pill itself.
    var hideRewriteCompletionLabel: Bool = false

    enum CodingKeys: String, CodingKey {
        case hotkeyMode
        case hasSeenOnboarding
        case alwaysLocalTranscription
        case selectedLocalTranscriptionModelName
        case selectedLocalTranscriptionBackend
        case hasAutoSelectedFastLocalModel
        case hasDismissedInputMonitoringHint
        case dockModeEnabled
        case autoFallbackToLocalOnOffline
        case rewritingProviderMode
        case recordingOverlayMode
        case rewriteConsents
        case hideRewriteCompletionLabel
    }
}

extension AppSettings {
    /// Legacy key from before `secureLocalModeEnabled` was renamed to `alwaysLocalTranscription`
    /// and decoupled from rewrite-workflow availability.
    private enum LegacyCodingKeys: String, CodingKey {
        case secureLocalModeEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hotkeyMode = try container.decodeIfPresent(HotkeyMode.self, forKey: .hotkeyMode) ?? .hold
        hasSeenOnboarding = try container.decodeIfPresent(Bool.self, forKey: .hasSeenOnboarding) ?? false
        if let migrated = try container.decodeIfPresent(Bool.self, forKey: .alwaysLocalTranscription) {
            alwaysLocalTranscription = migrated
        } else {
            let legacyContainer = try? decoder.container(keyedBy: LegacyCodingKeys.self)
            alwaysLocalTranscription = (try legacyContainer?.decodeIfPresent(Bool.self, forKey: .secureLocalModeEnabled)) ?? false
        }
        selectedLocalTranscriptionModelName = try container.decodeIfPresent(
            String.self,
            forKey: .selectedLocalTranscriptionModelName
        ) ?? LocalTranscriptionService.recommendedFastModelName
        selectedLocalTranscriptionBackend = try container.decodeIfPresent(
            LocalTranscriptionBackend.self,
            forKey: .selectedLocalTranscriptionBackend
        ) ?? .appleSpeech
        hasAutoSelectedFastLocalModel = try container.decodeIfPresent(
            Bool.self,
            forKey: .hasAutoSelectedFastLocalModel
        ) ?? false
        hasDismissedInputMonitoringHint = try container.decodeIfPresent(
            Bool.self,
            forKey: .hasDismissedInputMonitoringHint
        ) ?? false
        dockModeEnabled = try container.decodeIfPresent(Bool.self, forKey: .dockModeEnabled) ?? true
        autoFallbackToLocalOnOffline = try container.decodeIfPresent(
            Bool.self,
            forKey: .autoFallbackToLocalOnOffline
        ) ?? false
        rewritingProviderMode = try container.decodeIfPresent(
            RewriteProviderMode.self,
            forKey: .rewritingProviderMode
        ) ?? .auto
        recordingOverlayMode = try container.decodeIfPresent(
            RecordingOverlayMode.self,
            forKey: .recordingOverlayMode
        ) ?? .screenBottomCenter
        rewriteConsents = try container.decodeIfPresent(
            [WorkflowType: OnlineProvider].self,
            forKey: .rewriteConsents
        ) ?? [:]
        hideRewriteCompletionLabel = try container.decodeIfPresent(
            Bool.self,
            forKey: .hideRewriteCompletionLabel
        ) ?? false
    }
}

enum LocalTranscriptionBackend: String, Codable, CaseIterable, Identifiable {
    case appleSpeech
    case whisperKit

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .appleSpeech: return "Apple-Gerätetranskription"
        case .whisperKit: return "WhisperKit"
        }
    }
}

enum RecordingOverlayMode: String, Codable, CaseIterable, Identifiable {
    case off
    case screenBottomCenter

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .off: return "Aus"
        case .screenBottomCenter: return "Unten mittig im Zielbildschirm"
        }
    }

    init(from decoder: Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(String.self)
        if rawValue == "textCursor" {
            self = .screenBottomCenter
        } else if let mode = RecordingOverlayMode(rawValue: rawValue) {
            self = mode
        } else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "Unbekannter Aufnahmeanzeige-Modus.")
            )
        }
    }
}

enum TranscriptionBackend: String, Codable {
    case remote
    case local
}

// MARK: - Workflow Settings

enum LiveSmoothingBackend: String, Codable, CaseIterable, Identifiable {
    case off
    case onDevice
    case online

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .off: return "Aus"
        case .onDevice: return "Auf diesem Mac"
        case .online: return "Online (Groq/OpenAI)"
        }
    }
}

struct TranscriptionSettings: Codable, Equatable {
    var language: String = "de"
    var liveSmoothingBackend: LiveSmoothingBackend = .off
    var livePillMaxLines: Int = 8

    enum CodingKeys: String, CodingKey {
        case language
        case liveSmoothingBackend
        case livePillMaxLines
    }
}

extension TranscriptionSettings {
    private enum LegacyCodingKeys: String, CodingKey {
        case liveSmoothingEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        language = try container.decodeIfPresent(String.self, forKey: .language) ?? "de"
        if let backend = try container.decodeIfPresent(LiveSmoothingBackend.self, forKey: .liveSmoothingBackend) {
            liveSmoothingBackend = backend
        } else {
            let legacyContainer = try? decoder.container(keyedBy: LegacyCodingKeys.self)
            let legacyEnabled = (try? legacyContainer?.decodeIfPresent(Bool.self, forKey: .liveSmoothingEnabled)) ?? false
            liveSmoothingBackend = legacyEnabled ? .onDevice : .off
        }
        let rawMaxLines = try container.decodeIfPresent(Int.self, forKey: .livePillMaxLines) ?? 8
        livePillMaxLines = min(max(rawMaxLines, 1), 20)
    }
}

struct DampfAblassenSettings: Codable, Equatable {
    var systemPrompt: String = "Du bekommst ein gesprochenes, oft langes und wütendes Transkript. Schreibe daraus EINEN kurzen Absatz in der Ich-Perspektive der sprechenden Person — als würde sie selbst schreiben, nicht als Beschreibung über sie. Der Absatz sagt genau, was sie eigentlich will oder braucht — ohne Schimpfwörter, Drohungen oder Sarkasmus. Gib NUR diesen Absatz zurück. Kein Vorwort, keine Anrede, keine Grußformel, keine Platzhalter, keine Erklärung, kein Satz über die Aufgabe selbst."
    var customName: String = ""
}

struct EmojiTextSettings: Codable, Equatable {
    var emojiDensity: EmojiDensity = .mittel
    var customName: String = ""

    enum EmojiDensity: String, Codable, CaseIterable, Identifiable {
        case wenig
        case mittel
        case viel

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .wenig: return "Wenig"
            case .mittel: return "Mittel"
            case .viel: return "Viel"
            }
        }
    }
}

struct TextImprovementSettings: Codable, Equatable {
    var systemPrompt: String = """
    Überarbeite den folgenden per Spracheingabe transkribierten Text.

    Ziel:
    Der Text soll wie ein bewusst formulierter schriftlicher Text wirken, nicht wie eine Sprachnachricht.

    Regeln:
    - Entferne Füllwörter wie „ähm“, „äh“, „also“, „ja“, „genau“, sofern sie keine Bedeutung tragen.
    - Entferne doppelte Satzanfänge und Selbstkorrekturen.
    - Glätte holprige Formulierungen.
    - Korrigiere Grammatik, Zeichensetzung und Groß-/Kleinschreibung.
    - Erhalte Inhalt, Aussageabsicht und Ton.
    - Erfinde keine neuen Fakten.
    - Formuliere klar, flüssig und natürlich.
    - Bei unvollständigen Gedanken: sinnvoll glätten, aber nicht inhaltlich ausbauen.
    - Gib nur den überarbeiteten Text aus, keine Erklärung.
    """
    var customTerms: [String] = []
    var context: String = "Lehrkraft in vertrauter schulischer Umgebung in der sich alle duzen."
    var tone: TextTone = .neutral
    var customName: String = ""

    enum TextTone: String, Codable, CaseIterable, Identifiable {
        case formal
        case neutral
        case casual

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .formal: return "Formell"
            case .neutral: return "Neutral"
            case .casual: return "Locker"
            }
        }
    }
}
