enum TranscriptionModeIconTone: Equatable {
    case local
    case groq
    case fallback
}

struct TranscriptionModeStatus: Equatable {
    let alwaysLocalTranscription: Bool
    let selectedLocalBackend: LocalTranscriptionBackend
    let appleSpeechAvailable: Bool
    let selectedLocalModelInstalled: Bool
    let selectedLocalModelDisplayName: String
    let isDownloadingLocalModel: Bool
    let localModelDownloadStatusText: String?
    let hasGroqKey: Bool
    let groqFallbackActive: Bool
    let groqQuotaUsedToday: String

    var menuBarCloudIndicator: MenuBarCloudIndicator {
        if alwaysLocalTranscription { return .none }
        if hasGroqKey && !groqFallbackActive { return .groqReady }
        return .openAIFallback
    }

    var panelIconName: String {
        if alwaysLocalTranscription { return "lock.shield.fill" }
        return groqFallbackActive ? "eurosign.circle" : "network"
    }

    var panelIconTone: TranscriptionModeIconTone {
        if alwaysLocalTranscription { return .local }
        if hasGroqKey && !groqFallbackActive { return .groq }
        return .fallback
    }

    var panelTitle: String {
        alwaysLocalTranscription ? "Lokal · kein Server" : "Online · \(onlineTitle)"
    }

    var onlineTitle: String {
        hasGroqKey && !groqFallbackActive ? "Groq Whisper" : "OpenAI Whisper"
    }

    var panelSubtitle: String {
        if alwaysLocalTranscription {
            if selectedLocalBackend == .appleSpeech {
                return appleSpeechAvailable
                    ? "Verarbeitung auf diesem Gerät mit Apple-Gerätetranskription."
                    : "Apple-Gerätetranskription ist nicht verfügbar."
            }
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
        if alwaysLocalTranscription {
            if selectedLocalBackend == .appleSpeech {
                return appleSpeechAvailable
                    ? "Lokal: Apple-Gerätetranskription."
                    : "Apple-Gerätetranskription ist nicht verfügbar."
            }
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
