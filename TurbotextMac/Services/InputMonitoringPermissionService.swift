import Cocoa

@MainActor
enum InputMonitoringPermissionService {
    static func currentStatus() -> Bool {
        CGPreflightListenEventAccess()
    }
}
