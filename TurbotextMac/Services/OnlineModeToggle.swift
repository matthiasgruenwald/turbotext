import Foundation

/// Pure decision logic for the main-window online/offline switch.
/// The switch represents "Online" (on = online, off = offline/local) — switching to
/// offline is only allowed once the local model is installed (see ADR for secure local mode).
enum OnlineModeToggle {
    static func nextAlwaysLocalTranscription(requestedOnline: Bool, localModelInstalled: Bool, appleSpeechAvailable: Bool = false) -> Bool? {
        if requestedOnline { return false }
        return localModelInstalled || appleSpeechAvailable ? true : nil
    }

    static func isToggleEnabled(alwaysLocalTranscription: Bool, localModelInstalled: Bool, appleSpeechAvailable: Bool = false) -> Bool {
        alwaysLocalTranscription || localModelInstalled || appleSpeechAvailable
    }

    static func disabledReason(alwaysLocalTranscription: Bool, localModelInstalled: Bool, appleSpeechAvailable: Bool = false) -> String? {
        guard !isToggleEnabled(alwaysLocalTranscription: alwaysLocalTranscription, localModelInstalled: localModelInstalled, appleSpeechAvailable: appleSpeechAvailable) else {
            return nil
        }
        return "Lokales Modell muss erst installiert werden, um offline zu wechseln."
    }
}
