import Foundation

/// Pure decision logic for the main-window online/offline switch.
/// The switch represents "Online" (on = online, off = offline/local) — switching to
/// offline is only allowed once the selected local system is ready.
enum OnlineModeToggle {
    static func nextAlwaysLocalTranscription(
        requestedOnline: Bool,
        selectedLocalBackend: LocalTranscriptionBackend = .appleSpeech,
        localModelInstalled: Bool,
        appleSpeechAvailable: Bool = false
    ) -> Bool? {
        if requestedOnline { return false }
        return isSelectedLocalBackendReady(
            selectedLocalBackend: selectedLocalBackend,
            localModelInstalled: localModelInstalled,
            appleSpeechAvailable: appleSpeechAvailable
        ) ? true : nil
    }

    static func isToggleEnabled(
        alwaysLocalTranscription: Bool,
        selectedLocalBackend: LocalTranscriptionBackend = .appleSpeech,
        localModelInstalled: Bool,
        appleSpeechAvailable: Bool = false
    ) -> Bool {
        alwaysLocalTranscription || isSelectedLocalBackendReady(
            selectedLocalBackend: selectedLocalBackend,
            localModelInstalled: localModelInstalled,
            appleSpeechAvailable: appleSpeechAvailable
        )
    }

    static func disabledReason(
        alwaysLocalTranscription: Bool,
        selectedLocalBackend: LocalTranscriptionBackend = .appleSpeech,
        localModelInstalled: Bool,
        appleSpeechAvailable: Bool = false
    ) -> String? {
        guard !isToggleEnabled(
            alwaysLocalTranscription: alwaysLocalTranscription,
            selectedLocalBackend: selectedLocalBackend,
            localModelInstalled: localModelInstalled,
            appleSpeechAvailable: appleSpeechAvailable
        ) else {
            return nil
        }
        switch selectedLocalBackend {
        case .appleSpeech:
            return "Apple-Sprachassets müssen erst installiert werden, um offline zu wechseln."
        case .whisperKit:
            return "Das ausgewählte WhisperKit-Modell muss erst installiert werden, um offline zu wechseln."
        }
    }

    private static func isSelectedLocalBackendReady(
        selectedLocalBackend: LocalTranscriptionBackend,
        localModelInstalled: Bool,
        appleSpeechAvailable: Bool
    ) -> Bool {
        switch selectedLocalBackend {
        case .appleSpeech: return appleSpeechAvailable
        case .whisperKit: return localModelInstalled
        }
    }
}
