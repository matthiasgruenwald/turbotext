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

@Observable
@MainActor
final class HotkeyService {
    private var flagsMonitorGlobal: Any?
    private var flagsMonitorLocal: Any?
    private var keyDownMonitor: Any?
    private var keyUpMonitor: Any?
    private var activeCombo: WorkflowType?

    let store: ShortcutStore
    var onHotkeyEvent: ((HotkeyEvent) -> Void)?

    init(store: ShortcutStore) {
        self.store = store
    }

    func start() {
        flagsMonitorGlobal = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in self?.handleFlags(event) }
        }
        flagsMonitorLocal = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in self?.handleFlags(event) }
            return event
        }
        keyDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in self?.handleKeyDown(event) }
        }
        keyUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyUp) { [weak self] event in
            Task { @MainActor in self?.handleKeyUp(event) }
        }
    }

    func stop() {
        [flagsMonitorGlobal, flagsMonitorLocal, keyDownMonitor, keyUpMonitor]
            .compactMap { $0 }
            .forEach { NSEvent.removeMonitor($0) }
        flagsMonitorGlobal = nil
        flagsMonitorLocal = nil
        keyDownMonitor = nil
        keyUpMonitor = nil
    }

    private func handleFlags(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if let type = store.workflow(matching: flags) {
            if activeCombo == nil {
                activeCombo = type
                onHotkeyEvent?(.down(type))
            }
            return
        }

        if let combo = activeCombo {
            activeCombo = nil
            onHotkeyEvent?(.up(combo))
        }
    }

    private func handleKeyDown(_ event: NSEvent) {
        if event.keyCode == 53 {
            activeCombo = nil
            onHotkeyEvent?(.cancel)
            return
        }

        guard activeCombo == nil else { return }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if let type = store.workflow(matching: event.keyCode, flags: flags) {
            activeCombo = type
            onHotkeyEvent?(.down(type))
        }
    }

    private func handleKeyUp(_ event: NSEvent) {
        guard let combo = activeCombo else { return }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if store.shortcuts(for: combo).contains(where: { $0.matches(keyCode: event.keyCode, flags: flags) }) {
            activeCombo = nil
            onHotkeyEvent?(.up(combo))
        }
    }
}
