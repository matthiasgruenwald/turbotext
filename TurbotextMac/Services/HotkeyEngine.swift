import AppKit

// MARK: - Timer scheduling seam (testability only, no custom scheduling framework)

/// Cancellation handle returned by `HotkeyEngineTimerScheduling.scheduleRepeating`.
final class HotkeyEngineTimerToken {
    private let cancelAction: () -> Void
    private var cancelled = false

    init(cancelAction: @escaping () -> Void) {
        self.cancelAction = cancelAction
    }

    func cancel() {
        guard !cancelled else { return }
        cancelled = true
        cancelAction()
    }
}

protocol HotkeyEngineTimerScheduling {
    func scheduleRepeating(interval: TimeInterval, _ block: @escaping () -> Void) -> HotkeyEngineTimerToken
}

/// Real-world scheduler backed by `Timer`, used by `HotkeyService` in production.
final class RunLoopTimerScheduler: HotkeyEngineTimerScheduling {
    func scheduleRepeating(interval: TimeInterval, _ block: @escaping () -> Void) -> HotkeyEngineTimerToken {
        let timer = Timer(timeInterval: interval, repeats: true) { _ in block() }
        RunLoop.main.add(timer, forMode: .common)
        return HotkeyEngineTimerToken { timer.invalidate() }
    }
}

// MARK: - HotkeyEngine

/// Matching/hold-state logic for hotkeys, decoupled from NSEvent monitoring.
/// Consumes synthetic modifier-flag and keyCode sequences and produces `HotkeyEvent`s.
/// Owns the hold-state machine and the 80ms fallback timer (workaround for fn/Globe
/// key release events that macOS doesn't reliably fire on some non-Apple keyboards —
/// see "F-Key-Shortcut" in CONTEXT.md).
@MainActor
final class HotkeyEngine {
    private static let fallbackTimerInterval: TimeInterval = 0.08

    private let store: ShortcutStore
    private let timerScheduler: HotkeyEngineTimerScheduling
    private let currentFlags: () -> NSEvent.ModifierFlags

    private var activeCombo: WorkflowType?
    private var fallbackTimerToken: HotkeyEngineTimerToken?

    var onHotkeyEvent: ((HotkeyEvent) -> Void)?

    init(
        store: ShortcutStore,
        timerScheduler: HotkeyEngineTimerScheduling = RunLoopTimerScheduler(),
        currentFlags: @escaping () -> NSEvent.ModifierFlags = { NSEvent.modifierFlags }
    ) {
        self.store = store
        self.timerScheduler = timerScheduler
        self.currentFlags = currentFlags
    }

    func stop() {
        cancelFallbackTimer()
        activeCombo = nil
    }

    func handleFlagsChanged(_ rawFlags: NSEvent.ModifierFlags) {
        let flags = rawFlags.intersection(.deviceIndependentFlagsMask)

        if let type = store.workflow(matching: flags) {
            if activeCombo == nil {
                activeCombo = type
                onHotkeyEvent?(.down(type))
                startFallbackTimer(for: type)
            }
            return
        }

        if let combo = activeCombo {
            activeCombo = nil
            cancelFallbackTimer()
            onHotkeyEvent?(.up(combo))
        }
    }

    func handleKeyDown(keyCode: UInt16, flags rawFlags: NSEvent.ModifierFlags) {
        if keyCode == 53 {
            activeCombo = nil
            cancelFallbackTimer()
            onHotkeyEvent?(.cancel)
            return
        }

        guard activeCombo == nil else { return }

        let flags = rawFlags.intersection(.deviceIndependentFlagsMask)
        if let type = store.workflow(matching: keyCode, flags: flags) {
            activeCombo = type
            onHotkeyEvent?(.down(type))
        }
    }

    func handleKeyUp(keyCode: UInt16, flags rawFlags: NSEvent.ModifierFlags) {
        guard let combo = activeCombo else { return }
        let flags = rawFlags.intersection(.deviceIndependentFlagsMask)
        if store.shortcuts(for: combo).contains(where: { $0.matches(keyCode: keyCode, flags: flags) }) {
            activeCombo = nil
            cancelFallbackTimer()
            onHotkeyEvent?(.up(combo))
        }
    }

    // Backup for MacBook fn/globe key: flagsChanged may not fire reliably on release.
    // Polls current modifier flags every 80 ms and fires .up when the shortcut is no longer held.
    private func startFallbackTimer(for type: WorkflowType) {
        cancelFallbackTimer()
        let shortcuts = store.shortcuts(for: type)
        fallbackTimerToken = timerScheduler.scheduleRepeating(interval: Self.fallbackTimerInterval) { [weak self] in
            guard let self, self.activeCombo == type else { return }
            let current = self.currentFlags().intersection(.deviceIndependentFlagsMask)
            guard !shortcuts.contains(where: { $0.matches(flags: current) }) else { return }
            self.cancelFallbackTimer()
            self.activeCombo = nil
            self.onHotkeyEvent?(.up(type))
        }
    }

    private func cancelFallbackTimer() {
        fallbackTimerToken?.cancel()
        fallbackTimerToken = nil
    }
}
