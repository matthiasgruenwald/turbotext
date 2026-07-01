enum TranscriptionModeIconTone: Equatable {
    case local
    case groq
    case fallback
}

struct TranscriptionModeStatus: Equatable {
    let secureLocalModeEnabled: Bool
    let selectedLocalModelInstalled: Bool
    let selectedLocalModelDisplayName: String
    let isDownloadingLocalModel: Bool
    let localModelDownloadStatusText: String?
    let hasGroqKey: Bool
    let groqFallbackActive: Bool
    let groqQuotaUsedToday: String

    var menuBarCloudIndicator: MenuBarCloudIndicator {
        if secureLocalModeEnabled { return .none }
        if hasGroqKey && !groqFallbackActive { return .groqReady }
        return .openAIFallback
    }

    var panelIconName: String {
        if secureLocalModeEnabled { return "lock.shield.fill" }
        return groqFallbackActive ? "eurosign.circle" : "network"
    }

    var panelIconTone: TranscriptionModeIconTone {
        if secureLocalModeEnabled { return .local }
        if hasGroqKey && !groqFallbackActive { return .groq }
        return .fallback
    }

    var panelTitle: String {
        secureLocalModeEnabled ? "Lokal · kein Server" : "Online · \(onlineTitle)"
    }

    var onlineTitle: String {
        hasGroqKey && !groqFallbackActive ? "Groq Whisper" : "OpenAI Whisper"
    }

    var panelSubtitle: String {
        if secureLocalModeEnabled {
            if isDownloadingLocalModel {
                return localModelDownloadStatusText ?? "Lokales Modell wird geladen."
            }
            if selectedLocalModelInstalled {
                return "Verarbeitung auf diesem Gerät mit \(selectedLocalModelDisplayName)."
            }
            return "\(selectedLocalModelDisplayName) ist noch nicht installiert."
        }

        if hasGroqKey {
            if groqFallbackActive {
                return "Über Server verarbeitet · Groq-Kontingent aufgebraucht, jetzt OpenAI Whisper."
            }
            return "Über Server verarbeitet · heute \(groqQuotaUsedToday) Groq-Kontingent genutzt."
        }

        return "Über Server verarbeitet via OpenAI Whisper."
    }

    var transcriptionWorkflowSubtitle: String {
        if secureLocalModeEnabled {
            return selectedLocalModelInstalled
                ? "Lokal: \(selectedLocalModelDisplayName)."
                : "Lokales WhisperKit-Modell fehlt."
        }
        return "Sprache rein. Landet in Zwischenablage."
    }

    func localInstallStatusText(installedModelCount: Int) -> String {
        selectedLocalModelInstalled
            ? "\(installedModelCount) lokales WhisperKit-Modell installiert."
            : "Das ausgewählte Modell wird beim Installieren lokal gespeichert."
    }
}
