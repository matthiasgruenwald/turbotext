import AppKit

enum DockModeService {
    static func policy(forDockModeEnabled dockModeEnabled: Bool) -> NSApplication.ActivationPolicy {
        dockModeEnabled ? .regular : .accessory
    }

    @MainActor
    static func apply(dockModeEnabled: Bool) {
        NSApp.setActivationPolicy(policy(forDockModeEnabled: dockModeEnabled))
    }
}
