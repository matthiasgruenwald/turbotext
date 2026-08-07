/// The concrete transcription backend chosen for a spoken workflow. Distinct from
/// `TranscriptionBackend` (which only distinguishes remote/local for UI copy) because
/// `.local` now covers two different implementations — Apple Speech and WhisperKit.
enum ResolvedTranscriptionBackend: Equatable {
    case appleSpeech
    case remote
    case whisperKit
    case unavailable
}

/// Chooses which transcription backend a spoken workflow (Transkription, Turbotext+,
/// Dampf ablassen, Emoji-Text) should use, replacing the direct
/// `alwaysLocalTranscription ? .local : .remote` checks that used to live in
/// `AppState.makeWorkflow`. Fixed priority (Wayfinder #98/#123):
/// 1. Apple Speech, when "immer lokal transkribieren" is on and Apple Speech is available.
/// 2. Remote (Groq/Whisper), when online.
/// 3. Apple Speech as an automatic offline fallback, when the fallback toggle is on and offline.
/// 4. WhisperKit, only when a caller explicitly asks for the legacy local backend and a model is installed.
enum TranscriptionBackendResolver {
    static func resolve(
        alwaysLocalTranscription: Bool,
        selectedLocalBackend: LocalTranscriptionBackend = .appleSpeech,
        appleSpeechAvailable: Bool,
        isOnline: Bool,
        autoFallbackToLocalOnOffline: Bool,
        legacyWhisperKitRequested: Bool,
        whisperKitModelInstalled: Bool
    ) -> ResolvedTranscriptionBackend {
        if alwaysLocalTranscription {
            switch selectedLocalBackend {
            case .appleSpeech:
                return appleSpeechAvailable ? .appleSpeech : .unavailable
            case .whisperKit:
                return whisperKitModelInstalled ? .whisperKit : .unavailable
            }
        }
        if isOnline {
            return .remote
        }
        if autoFallbackToLocalOnOffline && appleSpeechAvailable {
            return .appleSpeech
        }
        if legacyWhisperKitRequested && whisperKitModelInstalled {
            return .whisperKit
        }
        return .remote
    }
}

/// What resolving to `.unavailable` actually rejects with (#192, fixes F2 from #188
/// fully) — a pure function of which local backend was selected and Apple Speech's
/// current readiness, so both the rejection message and the "should Turbotext start
/// installing Sprachassets now" decision are unit-testable without constructing
/// `AppState`. Applied by `AppState.unavailableResolvedTranscriber` regardless of
/// whether the caller would have routed live or file-based — unlike the pre-#192 check,
/// which only ran on the live path.
enum LocalBackendUnavailableRejection {
    static let whisperKitModelNotInstalledMessage = "Lokales Modell nicht installiert – in den Einstellungen herunterladen."

    static func resolve(
        selectedBackend: LocalTranscriptionBackend,
        appleSpeechReadiness: AppleSpeechReadiness
    ) -> (rejection: WorkflowStartRejection, shouldInstallAssets: Bool) {
        switch selectedBackend {
        case .appleSpeech:
            guard case .notReady(let status, let canInstall) = appleSpeechReadiness else {
                return (
                    WorkflowStartRejection(
                        reason: "appleSpeech.unknown",
                        message: "Apple-Gerätetranskription derzeit nicht verfügbar.",
                        canRetryImmediately: false
                    ),
                    false
                )
            }
            return (
                WorkflowStartRejection(
                    reason: "appleSpeech.\(String(describing: status))",
                    message: AppleSpeechUnavailableHint.refusalText(for: status),
                    canRetryImmediately: canInstall
                ),
                canInstall
            )
        case .whisperKit:
            return (
                WorkflowStartRejection(
                    reason: "localModelNotInstalled",
                    message: whisperKitModelNotInstalledMessage,
                    canRetryImmediately: false
                ),
                false
            )
        }
    }
}
