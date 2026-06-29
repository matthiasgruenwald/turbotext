import Foundation

// MARK: - Workflow Types

enum WorkflowType: String, CaseIterable, Identifiable, Codable {
    case transcription
    case localTranscription
    case textImprover
    case dampfAblassen
    case emojiText

    var id: String { rawValue }

    static var mainMenuCases: [WorkflowType] {
        allCases.filter { $0 != .localTranscription }
    }

    var displayName: String {
        switch self {
        case .transcription: return "Turbotext"
        case .localTranscription: return "Turbotext Lokal"
        case .textImprover: return "Turbotext+"
        case .dampfAblassen: return "Turbotext $%&!"
        case .emojiText: return "Turbotext :)"
        }
    }

    var icon: String {
        switch self {
        case .transcription: return "mic.fill"
        case .localTranscription: return "lock.shield.fill"
        case .textImprover: return "text.badge.checkmark"
        case .dampfAblassen: return "flame.fill"
        case .emojiText: return "face.smiling"
        }
    }

    var subtitle: String {
        switch self {
        case .transcription: return "Sprache rein. Text raus."
        case .localTranscription: return "Nur lokal. Kein Server."
        case .textImprover: return "Geschrieben sprechen."
        case .dampfAblassen: return "Frust rein. Entspannt raus."
        case .emojiText: return "Text rein. Emojis dazu."
        }
    }

    var accentColor: String {
        switch self {
        case .transcription: return "blue"
        case .localTranscription: return "green"
        case .textImprover: return "purple"
        case .dampfAblassen: return "orange"
        case .emojiText: return "cyan"
        }
    }
}

// MARK: - Workflow State

enum WorkflowPhase: Equatable {
    case idle
    case running(String)
    case done(String)
    case error(String)

    var isActive: Bool {
        switch self {
        case .idle: return false
        default: return true
        }
    }
}

enum WorkflowLaunchSource: Equatable {
    case manual
    case hotkeyBackground

    var presentsWorkflowPage: Bool {
        switch self {
        case .manual:
            return true
        case .hotkeyBackground:
            return false
        }
    }
}

typealias WorkflowOutputHandler = @MainActor (String) -> Void
typealias WorkflowPhaseChangeHandler = @MainActor (WorkflowPhase) -> Void

// MARK: - Workflow Protocol

@MainActor
protocol Workflow: AnyObject, Observable {
    var type: WorkflowType { get }
    var phase: WorkflowPhase { get set }
    var isRecording: Bool { get }
    var onOutput: WorkflowOutputHandler? { get set }
    var onPhaseChange: WorkflowPhaseChangeHandler? { get set }

    func start()
    func stop()
    func reset()
}

// MARK: - App Settings

struct AppSettings: Codable, Equatable {
    var hotkeyMode: HotkeyMode = .hold
    var hasSeenOnboarding: Bool = false
    var secureLocalModeEnabled: Bool = false
    var selectedLocalTranscriptionModelName: String = LocalTranscriptionService.recommendedFastModelName
    var hasAutoSelectedFastLocalModel: Bool = false
    var hasDismissedInputMonitoringHint: Bool = false
    var dockModeEnabled: Bool = true
    var autoFallbackToLocalOnOffline: Bool = false
    var rewritingProviderMode: RewriteProviderMode = .auto

    init(
        hotkeyMode: HotkeyMode = .hold,
        hasSeenOnboarding: Bool = false,
        secureLocalModeEnabled: Bool = false,
        selectedLocalTranscriptionModelName: String = LocalTranscriptionService.recommendedFastModelName,
        hasAutoSelectedFastLocalModel: Bool = false,
        hasDismissedInputMonitoringHint: Bool = false,
        dockModeEnabled: Bool = true,
        autoFallbackToLocalOnOffline: Bool = false,
        rewritingProviderMode: RewriteProviderMode = .auto
    ) {
        self.hotkeyMode = hotkeyMode
        self.hasSeenOnboarding = hasSeenOnboarding
        self.secureLocalModeEnabled = secureLocalModeEnabled
        self.selectedLocalTranscriptionModelName = selectedLocalTranscriptionModelName
        self.hasAutoSelectedFastLocalModel = hasAutoSelectedFastLocalModel
        self.hasDismissedInputMonitoringHint = hasDismissedInputMonitoringHint
        self.dockModeEnabled = dockModeEnabled
        self.autoFallbackToLocalOnOffline = autoFallbackToLocalOnOffline
        self.rewritingProviderMode = rewritingProviderMode
    }

    enum CodingKeys: String, CodingKey {
        case hotkeyMode
        case hasSeenOnboarding
        case secureLocalModeEnabled
        case selectedLocalTranscriptionModelName
        case hasAutoSelectedFastLocalModel
        case hasDismissedInputMonitoringHint
        case dockModeEnabled
        case autoFallbackToLocalOnOffline
        case rewritingProviderMode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hotkeyMode = try container.decodeIfPresent(HotkeyMode.self, forKey: .hotkeyMode) ?? .hold
        hasSeenOnboarding = try container.decodeIfPresent(Bool.self, forKey: .hasSeenOnboarding) ?? false
        secureLocalModeEnabled = try container.decodeIfPresent(Bool.self, forKey: .secureLocalModeEnabled) ?? false
        selectedLocalTranscriptionModelName = try container.decodeIfPresent(
            String.self,
            forKey: .selectedLocalTranscriptionModelName
        ) ?? LocalTranscriptionService.recommendedFastModelName
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
    }
}

enum TranscriptionBackend: String, Codable {
    case remote
    case local
}

// MARK: - Workflow Settings

struct TranscriptionSettings: Codable {
    var language: String = "de"
}

struct DampfAblassenSettings: Codable {
    var systemPrompt: String = "Du erhältst ein emotional gesprochenes Transkript. Erkenne zuerst das eigentliche Ziel, Anliegen und den wahren Frust der Person. Formuliere daraus eine klare, respektvolle und wirksame Nachricht, mit der die Person ihr Ziel eher erreicht. Bewahre relevante Fakten, konkrete Probleme, Grenzen, Erwartungen und die nötige Dringlichkeit. Entferne Beleidigungen, Drohungen, Sarkasmus, Unterstellungen und unnötige Eskalation. Wenn mehrere Vorwürfe genannt werden, verdichte sie auf die entscheidenden Kernpunkte. Der Ton soll ruhig, menschlich, bestimmt und lösungsorientiert sein. Gib AUSSCHLIESSLICH die fertige Nachricht zurück. Antworte NIEMALS als Assistent, stelle KEINE Rückfragen und beginne KEIN Gespräch — auch wenn der Text kurz oder unklar wirkt."
    var customName: String = ""
}

struct EmojiTextSettings: Codable {
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

struct TextImprovementSettings: Codable {
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
