import Foundation

/// Pure decision logic for the main-window online/offline switch.
/// The switch represents "Online" (on = online, off = offline/local) — switching to
/// offline is only allowed once the local model is installed (see ADR for secure local mode).
enum OnlineModeToggle {
    static func nextAlwaysLocalTranscription(requestedOnline: Bool, localModelInstalled: Bool) -> Bool? {
        if requestedOnline { return false }
        return localModelInstalled ? true : nil
    }

    static func isToggleEnabled(alwaysLocalTranscription: Bool, localModelInstalled: Bool) -> Bool {
        alwaysLocalTranscription || localModelInstalled
    }

    static func disabledReason(alwaysLocalTranscription: Bool, localModelInstalled: Bool) -> String? {
        guard !isToggleEnabled(alwaysLocalTranscription: alwaysLocalTranscription, localModelInstalled: localModelInstalled) else {
            return nil
        }
        return "Lokales Modell muss erst installiert werden, um offline zu wechseln."
    }
}
