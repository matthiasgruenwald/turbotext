import Foundation

/// Pure decision logic for the main-window online/offline switch.
/// The switch represents "Online" (on = online, off = offline/local) — switching to
/// offline is only allowed once the local model is installed (see ADR for secure local mode).
enum OnlineModeToggle {
    static func nextSecureLocalModeEnabled(requestedOnline: Bool, localModelInstalled: Bool) -> Bool? {
        if requestedOnline { return false }
        return localModelInstalled ? true : nil
    }

    static func isToggleEnabled(secureLocalModeEnabled: Bool, localModelInstalled: Bool) -> Bool {
        secureLocalModeEnabled || localModelInstalled
    }
}
