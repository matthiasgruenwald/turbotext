import SwiftUI

@main
struct TurbotextMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var menuBarStatusCoordinator: MenuBarStatusCoordinator!
    private var mainWindowController: MainWindowController!
    private var prewarmObserver: PrewarmObserver!
    private var dockModeObserver: DockModeObserver!
    let appState = AppState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        prewarmObserver = PrewarmObserver(prewarm: { [weak appState] in
            appState?.prewarmLocalTranscriptionIfNeeded()
        })
        dockModeObserver = DockModeObserver(apply: { dockModeEnabled in
            DockModeService.apply(dockModeEnabled: dockModeEnabled)
        })
        appState.onAppSettingsChanged = { [weak prewarmObserver, weak dockModeObserver] old, new in
            prewarmObserver?.handleSettingsChange(old: old, new: new)
            dockModeObserver?.handleSettingsChange(old: old, new: new)
        }

        menuBarStatusCoordinator = MenuBarStatusCoordinator(
            orchestrator: appState.workflowLifecycle.orchestrator,
            fallbackManager: appState.fallbackManager,
            networkPingService: appState.networkPingService,
            cloudIndicatorProvider: { [weak appState] in
                appState?.transcriptionModeStatus.menuBarCloudIndicator ?? .none
            },
            groqQuotaUsedTodayProvider: { [weak appState] in
                appState?.quotaManager.formattedUsedToday
            }
        )
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            menuBarStatusCoordinator.attach(to: button)
            button.action = #selector(togglePopover)
            button.target = self
        }

        popover = NSPopover()
        popover.contentSize = NSSize(width: 340, height: 480)
        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: MenuBarView(appState: appState))

        mainWindowController = MainWindowController(makeWindow: { [weak self] in
            self?.makeMainWindow() ?? NSWindow()
        })

        DockModeService.apply(dockModeEnabled: appState.appSettings.dockModeEnabled)
        appState.prewarmLocalTranscriptionIfNeeded()

        // Hotkey events
        appState.hotkeyService.onHotkeyEvent = { [weak self] event in
            self?.handleHotkeyEvent(event)
        }
        appState.onPreferredContentSizeChange = { [weak self] size in
            self?.popover.contentSize = size
        }
        appState.onCloudIndicatorRefreshNeeded = { [weak self] in
            self?.refreshMenuBarCloudIndicator()
        }
        appState.refreshAccessibilityPermission()
        refreshMenuBarCloudIndicator()
        appState.hotkeyService.start()

        // Listen for popover dismiss requests (from auto-paste)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDismissPopover),
            name: .dismissPopover,
            object: nil
        )

        DispatchQueue.main.async { [weak self] in
            self?.showOnboardingIfNeeded()
        }
    }

    private func refreshMenuBarCloudIndicator() {
        menuBarStatusCoordinator.refreshCloudIndicator()
        menuBarStatusCoordinator.updatePermissions(
            accessibilityGranted: appState.accessibilityPermissionGranted,
            inputMonitoringGranted: appState.inputMonitoringPermissionGranted
        )
    }

    @objc private func handleDismissPopover() {
        appState.isPopoverShown = false
        popover.performClose(nil)
    }

    private func handleHotkeyEvent(_ event: HotkeyEvent) {
        switch event {
        case .down(let type):
            handleHotkeyDown(type)
        case .up(let type):
            handleHotkeyUp(type)
        case .cancel:
            handleHotkeyCancel()
        }
    }

    private func handleHotkeyDown(_ type: WorkflowType) {
        guard appState.isConfigured else { return }

        let fallback = TranscriptionFallbackResolver.resolve(
            for: appState.networkPingService.status,
            workflowType: type,
            autoFallbackToLocalOnOffline: appState.appSettings.autoFallbackToLocalOnOffline,
            isLocalModelInstalled: appState.selectedLocalModelIsInstalled
        )

        if let soundKind = fallback.soundKind {
            OfflineWarningSoundPlayer.play(soundKind)
        }

        let backendOverride: TranscriptionBackend? = type == .transcription ? fallback.backend : nil

        let mode = appState.appSettings.hotkeyMode

        switch mode {
        case .hold:
            // Hold mode: start recording on key down
            appState.startWorkflow(type, source: .hotkeyBackground, backendOverride: backendOverride)

        case .toggle:
            // Toggle mode: if already recording same workflow, stop it
            if let active = appState.activeWorkflow,
               active.type == type,
               active.phase.isActive {
                active.stop()
            } else {
                appState.prepareForPopoverPresentation()
                appState.startWorkflow(type, source: .manual, backendOverride: backendOverride)
                showPopover()
            }
        }
    }

    private func handleHotkeyUp(_ type: WorkflowType) {
        let mode = appState.appSettings.hotkeyMode

        guard mode == .hold else { return }

        // Hold mode: stop recording on key release
        if let active = appState.activeWorkflow,
           active.type == type {
            // Only stop if currently recording (running phase)
            if case .running = active.phase {
                active.stop()
            }
        }
    }

    private func handleHotkeyCancel() {
        appState.activeWorkflow?.stop()
    }

    @objc private func togglePopover() {
        let action = MenuBarClickDispatch.decide(
            mainWindowIsOpen: mainWindowController.isOpen,
            popoverIsShown: popover.isShown
        )

        switch action {
        case .bringMainWindowToFront:
            mainWindowController.bringToFrontIfOpen()
            NSApp.activate(ignoringOtherApps: true)
        case .closePopover:
            popover.performClose(nil)
            appState.isPopoverShown = false
        case .openPopover:
            appState.prepareForPopoverPresentation()
            showPopover()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        guard appState.appSettings.dockModeEnabled else { return true }
        appState.prepareForPopoverPresentation()
        mainWindowController.showOrCreate()
        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    private func makeMainWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Turbotext"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentViewController = NSHostingController(rootView: MenuBarView(appState: appState))
        window.center()
        return window
    }

    nonisolated func windowWillClose(_ notification: Notification) {
        Task { @MainActor in
            mainWindowController.windowWillClose()
        }
    }

    private func showOnboardingIfNeeded() {
        guard appState.shouldShowOnboarding else { return }
        appState.prepareForPopoverPresentation()
        showPopover()
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        appState.isPopoverShown = true
        NSApp.activate(ignoringOtherApps: true)
    }

    nonisolated func popoverDidClose(_ notification: Notification) {
        Task { @MainActor in
            appState.isPopoverShown = false
            switch appState.currentPhase {
            case .done, .error:
                appState.resetCurrentWorkflow()
            default:
                appState.page = .main
            }
        }
    }
}
