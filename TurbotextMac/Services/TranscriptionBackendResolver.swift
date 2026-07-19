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
