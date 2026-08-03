import AppKit
import SwiftUI

/// Borderless, non-activating panel so the guide never steals focus from
/// System Settings — the drag must land in the TCC list, not here.
private final class PermissionGuidePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Owns the floating permission guide panel and keeps it positioned next to
/// the System Settings window while the onboarding flow runs (#156).
@MainActor
final class PermissionGuidePanelController: PermissionGuidePanelShowing {
    private let coordinator: PermissionGuideCoordinator
    private let settingsWindowFrame: () -> CGRect?
    private var panel: PermissionGuidePanel?

    init(
        coordinator: PermissionGuideCoordinator,
        settingsWindowFrame: @escaping () -> CGRect? = { SystemSettingsWindowFinder.currentFrame() }
    ) {
        self.coordinator = coordinator
        self.settingsWindowFrame = settingsWindowFrame
    }

    func showGuide() {
        let activePanel = panel ?? makePanel()
        panel = activePanel
        fitContent(of: activePanel)
        reposition(activePanel)
        activePanel.orderFrontRegardless()
    }

    func hideGuide() {
        panel?.orderOut(nil)
    }

    func repositionGuide() {
        guard let panel, panel.isVisible else { return }
        reposition(panel)
    }

    private func makePanel() -> PermissionGuidePanel {
        let panel = PermissionGuidePanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 220),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false
        panel.collectionBehavior = [.auxiliary, .fullScreenAuxiliary, .canJoinAllSpaces, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: PermissionGuideView(coordinator: coordinator))
        return panel
    }

    private func fitContent(of panel: PermissionGuidePanel) {
        guard let hostingView = panel.contentView as? NSHostingView<PermissionGuideView> else { return }
        let size = hostingView.fittingSize
        hostingView.frame = NSRect(origin: .zero, size: size)
        panel.setContentSize(size)
    }

    private func reposition(_ panel: NSPanel) {
        let primaryHeight = (NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.screens.first)?.frame.height ?? 0
        let settingsFrame = settingsWindowFrame().map {
            PermissionGuidePanelPositioning.appKitFrame(fromCGFrame: $0, primaryScreenHeight: primaryHeight)
        }
        let screen = settingsFrame.flatMap(screenContaining) ?? NSScreen.main
        let origin = PermissionGuidePanelPositioning.origin(
            settingsFrame: settingsFrame,
            panelSize: panel.frame.size,
            screenFrame: screen?.visibleFrame
        )
        panel.setFrameOrigin(origin)
    }

    private func screenContaining(_ frame: CGRect) -> NSScreen? {
        NSScreen.screens.first { $0.frame.intersects(frame) }
    }
}
