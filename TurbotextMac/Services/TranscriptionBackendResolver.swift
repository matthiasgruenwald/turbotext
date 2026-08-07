/// The concrete transcription backend chosen for a spoken workflow. Distinct from
/// `TranscriptionBackend` (which only distinguishes remote/local for UI copy) because
/// `.local` now covers two different implementations — Apple Speech and WhisperKit.
enum ResolvedTranscriptionBackend: Equatable {
    case appleSpeech
    case remote
    case whisperKit
    case unavailable
}

/// What one hotkey press decides (#193): the resolved backend and the warning sound that
/// belongs to it, if any. Before #193 these were two separate deciders — this resolver and
/// `TranscriptionFallbackResolver` (removed) — reading overlapping inputs at different
/// times, so the sound could describe a different backend than the one actually used
/// (e.g. a "network unavailable" chime while a rewrite workflow silently fell back to Apple
/// Speech). `warningSound` is `nil` whenever no chime should play — online, or
/// `alwaysLocalTranscription`, both of which never touch the network at all.
struct TranscriptionBackendDecision: Equatable {
    let backend: ResolvedTranscriptionBackend
    let warningSound: OfflineWarningSoundKind?
}

/// Chooses which transcription backend a spoken workflow (Transkription, Turbotext+,
/// Dampf ablassen, Emoji-Text) should use, and which warning sound — if any — belongs to
/// that choice, replacing the direct `alwaysLocalTranscription ? .local : .remote` checks
/// that used to live in `AppState.makeWorkflow`. Fixed priority (Wayfinder #98/#123):
/// 1. Apple Speech, when "immer lokal transkribieren" is on and Apple Speech is available.
/// 2. Remote (Groq/Whisper), when online.
/// 3. Apple Speech as an automatic offline fallback, when the fallback toggle is on and offline.
/// 4. WhisperKit, only when the legacy local backend is selected in settings and a model is
///    installed — derived from `selectedLocalBackend` rather than a caller-supplied override
///    (#193), so there is exactly one place a workflow's backend gets decided.
enum TranscriptionBackendResolver {
    static func resolve(
        alwaysLocalTranscription: Bool,
        selectedLocalBackend: LocalTranscriptionBackend = .appleSpeech,
        appleSpeechAvailable: Bool,
        isOnline: Bool,
        autoFallbackToLocalOnOffline: Bool,
        whisperKitModelInstalled: Bool
    ) -> TranscriptionBackendDecision {
        if alwaysLocalTranscription {
            switch selectedLocalBackend {
            case .appleSpeech:
                let backend: ResolvedTranscriptionBackend = appleSpeechAvailable ? .appleSpeech : .unavailable
                return TranscriptionBackendDecision(backend: backend, warningSound: nil)
            case .whisperKit:
                let backend: ResolvedTranscriptionBackend = whisperKitModelInstalled ? .whisperKit : .unavailable
                return TranscriptionBackendDecision(backend: backend, warningSound: nil)
            }
        }
        if isOnline {
            return TranscriptionBackendDecision(backend: .remote, warningSound: nil)
        }
        if autoFallbackToLocalOnOffline && appleSpeechAvailable {
            return TranscriptionBackendDecision(backend: .appleSpeech, warningSound: .localFallbackActive)
        }
        if selectedLocalBackend == .whisperKit && whisperKitModelInstalled {
            return TranscriptionBackendDecision(backend: .whisperKit, warningSound: .localFallbackActive)
        }
        return TranscriptionBackendDecision(backend: .remote, warningSound: .networkUnavailable)
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
