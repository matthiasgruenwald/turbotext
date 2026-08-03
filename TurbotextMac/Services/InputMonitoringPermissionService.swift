import Cocoa

@MainActor
enum InputMonitoringPermissionService {
    static func currentStatus() -> Bool {
        CGPreflightListenEventAccess()
    }

    static func requestPermissionPrompt() -> Bool {
        CGRequestListenEventAccess()
    }
}
