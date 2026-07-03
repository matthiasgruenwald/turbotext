import Cocoa
import Observation

enum HotkeyMode: String, Codable, CaseIterable, Identifiable {
    case hold    // Tasten halten = aufnehmen, loslassen = stoppen
    case toggle  // Einmal drücken = starten, nochmal/Escape = stoppen

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .hold: return "Halten"
        case .toggle: return "Drücken"
        }
    }

    var description: String {
        switch self {
        case .hold: return "Tasten halten zum Aufnehmen, loslassen zum Stoppen"
        case .toggle: return "Einmal drücken zum Starten, nochmal oder Escape zum Stoppen"
        }
    }
}

/// Workflow-level trigger emitted by `HotkeyCaptureService`. Deliberately expressed
/// in terms of `WorkflowType`, not raw NSEvent down/up — callers react to "this
/// workflow was activated/deactivated", not to platform key-event detail.
enum HotkeyTrigger {
    case activate(WorkflowType)
    case deactivate(WorkflowType)
    case cancelActive
}

// MARK: - Monitor installation seam (testability only, no custom event framework)

/// Cancellation handle returned by `HotkeyMonitorInstalling.install`.
final class HotkeyMonitorToken {
    private let removeAction: () -> Void
    private var removed = false

    init(removeAction: @escaping () -> Void) {
        self.removeAction = removeAction
    }

    func remove() {
        guard !removed else { return }
        removed = true
        removeAction()
    }
}

@MainActor
protocol HotkeyMonitorInstalling {
    func install(
        onFlagsChanged: @escaping (NSEvent.ModifierFlags) -> Void,
        onKeyDown: @escaping (UInt16, NSEvent.ModifierFlags) -> Void,
        onKeyUp: @escaping (UInt16, NSEvent.ModifierFlags) -> Void
    ) -> HotkeyMonitorToken
}

/// Real-world installer backed by `NSEvent` global/local monitors, used in production.
final class NSEventHotkeyMonitorInstaller: HotkeyMonitorInstalling {
    func install(
        onFlagsChanged: @escaping (NSEvent.ModifierFlags) -> Void,
        onKeyDown: @escaping (UInt16, NSEvent.ModifierFlags) -> Void,
        onKeyUp: @escaping (UInt16, NSEvent.ModifierFlags) -> Void
    ) -> HotkeyMonitorToken {
        let flagsGlobal = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { event in
            Task { @MainActor in onFlagsChanged(event.modifierFlags) }
        }
        let flagsLocal = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            Task { @MainActor in onFlagsChanged(event.modifierFlags) }
            return event
        }
        let keyDown = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            Task { @MainActor in onKeyDown(event.keyCode, event.modifierFlags) }
        }
        let keyUp = NSEvent.addGlobalMonitorForEvents(matching: .keyUp) { event in
            Task { @MainActor in onKeyUp(event.keyCode, event.modifierFlags) }
        }
        return HotkeyMonitorToken {
            [flagsGlobal, flagsLocal, keyDown, keyUp]
                .compactMap { $0 }
                .forEach { NSEvent.removeMonitor($0) }
        }
    }
}

// MARK: - Permission requesting seam

@MainActor
protocol HotkeyPermissionRequesting {
    func requestListenEventAccess()
}

/// Real-world requester backed by the Input Monitoring TCC prompt, used in production.
final class SystemHotkeyPermissionRequester: HotkeyPermissionRequesting {
    func requestListenEventAccess() {
        _ = InputMonitoringPermissionService.requestPermissionPrompt()
    }
}

// MARK: - HotkeyCaptureService

/// Owns the full path from system key event to workflow trigger: NSEvent monitoring,
/// the Input Monitoring permission prompt, hold-state matching (via `HotkeyEngine`),
/// and the 80ms fn/Globe-key-release workaround timer — all as internal implementation.
/// Public interface emits `HotkeyTrigger`s keyed on `WorkflowType`, not raw down/up events.
@Observable
@MainActor
final class HotkeyCaptureService {
    private let monitorInstaller: HotkeyMonitorInstalling
    private let permissionRequester: HotkeyPermissionRequesting
    private let engine: HotkeyEngine
    private var monitorToken: HotkeyMonitorToken?

    let store: ShortcutStore
    var onTrigger: ((HotkeyTrigger) -> Void)?

    convenience init(store: ShortcutStore) {
        self.init(
            store: store,
            monitorInstaller: NSEventHotkeyMonitorInstaller(),
            permissionRequester: SystemHotkeyPermissionRequester()
        )
    }

    init(
        store: ShortcutStore,
        monitorInstaller: HotkeyMonitorInstalling,
        permissionRequester: HotkeyPermissionRequesting
    ) {
        self.store = store
        self.monitorInstaller = monitorInstaller
        self.permissionRequester = permissionRequester
        self.engine = HotkeyEngine(store: store)
        engine.onHotkeyEvent = { [weak self] event in
            self?.forward(event)
        }
    }

    func start() {
        // Trigger the Input Monitoring TCC prompt — required for the global
        // keyDown/keyUp monitors below to receive any events at all.
        permissionRequester.requestListenEventAccess()
        monitorToken = monitorInstaller.install(
            onFlagsChanged: { [weak self] flags in self?.engine.handleFlagsChanged(flags) },
            onKeyDown: { [weak self] keyCode, flags in self?.engine.handleKeyDown(keyCode: keyCode, flags: flags) },
            onKeyUp: { [weak self] keyCode, flags in self?.engine.handleKeyUp(keyCode: keyCode, flags: flags) }
        )
    }

    func stop() {
        engine.stop()
        monitorToken?.remove()
        monitorToken = nil
    }

    private func forward(_ event: HotkeyEvent) {
        switch event {
        case .down(let type):
            onTrigger?(.activate(type))
        case .up(let type):
            onTrigger?(.deactivate(type))
        case .cancel:
            onTrigger?(.cancelActive)
        }
    }
}
