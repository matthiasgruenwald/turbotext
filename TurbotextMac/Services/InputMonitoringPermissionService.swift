import Cocoa

@MainActor
enum InputMonitoringPermissionService {
    static func currentStatus() -> Bool {
        CGPreflightListenEventAccess()
    }

    static func requestPermissionPrompt() -> Bool {
        CGRequestListenEventAccess()
    }

    static func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
