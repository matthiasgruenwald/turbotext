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
    let isOnline: Bool
    let autoFallbackToLocalOnOffline: Bool

    private var resolvedBackend: ResolvedTranscriptionBackend {
        TranscriptionBackendResolver.resolve(
            alwaysLocalTranscription: alwaysLocalTranscription,
            selectedLocalBackend: selectedLocalBackend,
            appleSpeechAvailable: appleSpeechAvailable,
            isOnline: isOnline,
            autoFallbackToLocalOnOffline: autoFallbackToLocalOnOffline,
            whisperKitModelInstalled: selectedLocalModelInstalled
        ).backend
    }

    private var usesOfflineFallback: Bool {
        !alwaysLocalTranscription && !isOnline && autoFallbackToLocalOnOffline && resolvedBackend == .appleSpeech
    }

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
        switch resolvedBackend {
        case .appleSpeech where usesOfflineFallback:
            return "Offline-Fallback · Apple"
        case .appleSpeech:
            return "Lokal · Apple"
        case .whisperKit:
            return "Lokal · WhisperKit"
        case .unavailable:
            return "Lokal · nicht nutzbar"
        case .remote:
            return "Online · \(onlineTitle)"
        }
    }

    var onlineTitle: String {
        hasGroqKey && !groqFallbackActive ? "Groq Whisper" : "OpenAI Whisper"
    }

    var panelSubtitle: String {
        switch resolvedBackend {
        case .appleSpeech:
            return usesOfflineFallback
                ? "Offline-Fallback: Apple-Gerätetranskription auf diesem Gerät."
                : "Verarbeitung auf diesem Gerät mit Apple-Gerätetranskription."
        case .whisperKit:
            return "Verarbeitung auf diesem Gerät mit \(selectedLocalModelDisplayName)."
        case .unavailable:
            if selectedLocalBackend == .whisperKit, isDownloadingLocalModel {
                return localModelDownloadStatusText ?? "Lokales Modell wird geladen."
            }
            return unavailableLocalBackendText
        case .remote where hasGroqKey:
            if groqFallbackActive {
                return "Über Server verarbeitet · Groq-Kontingent aufgebraucht, jetzt OpenAI Whisper."
            }
            return "Über Server verarbeitet · heute \(groqQuotaUsedToday) Groq-Kontingent genutzt."
        case .remote:
            return "Über Server verarbeitet via OpenAI Whisper."
        }
    }

    var transcriptionWorkflowSubtitle: String {
        switch resolvedBackend {
        case .appleSpeech:
            return usesOfflineFallback
                ? "Offline-Fallback: Apple-Gerätetranskription."
                : "Lokal: Apple-Gerätetranskription."
        case .whisperKit:
            return "Lokal: \(selectedLocalModelDisplayName)."
        case .unavailable:
            return unavailableLocalBackendText
        case .remote:
            return "Sprache rein. Landet in Zwischenablage."
        }
    }

    private var unavailableLocalBackendText: String {
        selectedLocalBackend == .appleSpeech
            ? "Apple-Gerätetranskription ist nicht nutzbar."
            : "\(selectedLocalModelDisplayName) ist nicht nutzbar, weil es nicht installiert ist."
    }

    func localInstallStatusText(installedModelCount: Int) -> String {
        selectedLocalModelInstalled
            ? "\(installedModelCount) lokales WhisperKit-Modell installiert."
            : "Das ausgewählte Modell wird beim Installieren lokal gespeichert."
    }
}
