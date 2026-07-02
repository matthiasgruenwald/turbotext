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

enum HotkeyEvent {
    case down(WorkflowType)
    case up(WorkflowType)
    case cancel
}

/// Thin NSEvent-monitor adapter. Forwards raw flagsChanged/keyDown/keyUp events
/// to `HotkeyEngine`, which owns all matching/hold-state/fallback-timer logic.
@Observable
@MainActor
final class HotkeyService {
    private var flagsMonitorGlobal: Any?
    private var flagsMonitorLocal: Any?
    private var keyDownMonitor: Any?
    private var keyUpMonitor: Any?

    private let engine: HotkeyEngine

    let store: ShortcutStore
    var onHotkeyEvent: ((HotkeyEvent) -> Void)? {
        get { engine.onHotkeyEvent }
        set { engine.onHotkeyEvent = newValue }
    }

    init(store: ShortcutStore) {
        self.store = store
        self.engine = HotkeyEngine(store: store)
    }

    func start() {
        // Trigger the Input Monitoring TCC prompt — required for the global
        // keyDown/keyUp monitors below to receive any events at all.
        _ = CGRequestListenEventAccess()
        flagsMonitorGlobal = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in self?.engine.handleFlagsChanged(event.modifierFlags) }
        }
        flagsMonitorLocal = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in self?.engine.handleFlagsChanged(event.modifierFlags) }
            return event
        }
        keyDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in self?.engine.handleKeyDown(keyCode: event.keyCode, flags: event.modifierFlags) }
        }
        keyUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyUp) { [weak self] event in
            Task { @MainActor in self?.engine.handleKeyUp(keyCode: event.keyCode, flags: event.modifierFlags) }
        }
    }

    func stop() {
        engine.stop()
        [flagsMonitorGlobal, flagsMonitorLocal, keyDownMonitor, keyUpMonitor]
            .compactMap { $0 }
            .forEach { NSEvent.removeMonitor($0) }
        flagsMonitorGlobal = nil
        flagsMonitorLocal = nil
        keyDownMonitor = nil
        keyUpMonitor = nil
    }
}
