import XCTest
import AppKit
@testable import Turbotext

/// Fake scheduler: captures the fire block instead of using a real Timer,
/// so tests can trigger the 80ms fallback tick deterministically.
private final class FakeTimerScheduler: HotkeyEngineTimerScheduling {
    private(set) var lastInterval: TimeInterval?
    private var fireBlock: (() -> Void)?
    private(set) var cancelCallCount = 0

    func scheduleRepeating(interval: TimeInterval, _ block: @escaping () -> Void) -> HotkeyEngineTimerToken {
        lastInterval = interval
        fireBlock = block
        return HotkeyEngineTimerToken { [weak self] in
            self?.cancelCallCount += 1
            self?.fireBlock = nil
        }
    }

    func fire() {
        fireBlock?()
    }
}

@MainActor
final class HotkeyEngineTests: XCTestCase {

    private func makeStore() -> ShortcutStore {
        ShortcutStore(userDefaultsKey: "test_\(UUID().uuidString)")
    }

    // MARK: - Modifier-only hold matching

    func testFlagsChangeMatchingShortcutEmitsDown() {
        let store = makeStore()
        let scheduler = FakeTimerScheduler()
        let engine = HotkeyEngine(store: store, timerScheduler: scheduler, currentFlags: { [] })
        var events: [HotkeyEvent] = []
        engine.onHotkeyEvent = { events.append($0) }

        engine.handleFlagsChanged([.function, .shift])

        XCTAssertEqual(events.count, 1)
        guard case .down(.transcription) = events[0] else { return XCTFail("expected down(.transcription)") }
    }

    func testFlagsReleasedEmitsUp() {
        let store = makeStore()
        let scheduler = FakeTimerScheduler()
        let engine = HotkeyEngine(store: store, timerScheduler: scheduler, currentFlags: { [] })
        var events: [HotkeyEvent] = []
        engine.onHotkeyEvent = { events.append($0) }

        engine.handleFlagsChanged([.function, .shift])
        engine.handleFlagsChanged([])

        XCTAssertEqual(events.count, 2)
        guard case .up(.transcription) = events[1] else { return XCTFail("expected up(.transcription)") }
    }

    func testFlagsDownIsNotReemittedWhileHeld() {
        let store = makeStore()
        let scheduler = FakeTimerScheduler()
        let engine = HotkeyEngine(store: store, timerScheduler: scheduler, currentFlags: { [] })
        var events: [HotkeyEvent] = []
        engine.onHotkeyEvent = { events.append($0) }

        engine.handleFlagsChanged([.function, .shift])
        engine.handleFlagsChanged([.function, .shift])

        XCTAssertEqual(events.count, 1)
    }

    // MARK: - keyCode (F-key) matching

    func testKeyDownMatchingShortcutEmitsDown() {
        let store = makeStore()
        store.add(Shortcut(modifiers: [], keyCode: 96), for: .transcription)
        let scheduler = FakeTimerScheduler()
        let engine = HotkeyEngine(store: store, timerScheduler: scheduler, currentFlags: { [] })
        var events: [HotkeyEvent] = []
        engine.onHotkeyEvent = { events.append($0) }

        engine.handleKeyDown(keyCode: 96, flags: [])

        guard case .down(.transcription) = events.first else { return XCTFail("expected down") }
    }

    func testKeyUpMatchingActiveComboEmitsUp() {
        let store = makeStore()
        store.add(Shortcut(modifiers: [], keyCode: 96), for: .transcription)
        let scheduler = FakeTimerScheduler()
        let engine = HotkeyEngine(store: store, timerScheduler: scheduler, currentFlags: { [] })
        var events: [HotkeyEvent] = []
        engine.onHotkeyEvent = { events.append($0) }

        engine.handleKeyDown(keyCode: 96, flags: [])
        engine.handleKeyUp(keyCode: 96, flags: [])

        guard case .up(.transcription) = events.last else { return XCTFail("expected up") }
        XCTAssertEqual(events.count, 2)
    }

    func testEscapeKeyDownEmitsCancel() {
        let store = makeStore()
        let scheduler = FakeTimerScheduler()
        let engine = HotkeyEngine(store: store, timerScheduler: scheduler, currentFlags: { [] })
        var events: [HotkeyEvent] = []
        engine.onHotkeyEvent = { events.append($0) }

        engine.handleKeyDown(keyCode: 53, flags: [])

        guard case .cancel = events.first else { return XCTFail("expected cancel") }
    }

    // MARK: - 80ms fallback timer

    func testFallbackTimerUsesEightyMillisecondInterval() {
        let store = makeStore()
        let scheduler = FakeTimerScheduler()
        let engine = HotkeyEngine(store: store, timerScheduler: scheduler, currentFlags: { [] })

        engine.handleFlagsChanged([.function, .shift])

        XCTAssertEqual(scheduler.lastInterval, 0.08)
    }

    func testFallbackTimerFiresUpWhenFlagsNoLongerMatchWithoutExplicitRelease() {
        let store = makeStore()
        let scheduler = FakeTimerScheduler()
        var flags: NSEvent.ModifierFlags = [.function, .shift]
        let engine = HotkeyEngine(store: store, timerScheduler: scheduler, currentFlags: { flags })
        var events: [HotkeyEvent] = []
        engine.onHotkeyEvent = { events.append($0) }

        engine.handleFlagsChanged(flags)
        // Simulate the missing release flagsChanged event (e.g. Perixx fn/Globe key):
        // the OS never calls handleFlagsChanged([]) again, but the physical key is up.
        flags = []
        scheduler.fire()

        XCTAssertEqual(events.count, 2)
        guard case .up(.transcription) = events.last else { return XCTFail("expected fallback up") }
    }

    func testFallbackTimerDoesNothingWhileShortcutStillHeld() {
        let store = makeStore()
        let scheduler = FakeTimerScheduler()
        let flags: NSEvent.ModifierFlags = [.function, .shift]
        let engine = HotkeyEngine(store: store, timerScheduler: scheduler, currentFlags: { flags })
        var events: [HotkeyEvent] = []
        engine.onHotkeyEvent = { events.append($0) }

        engine.handleFlagsChanged(flags)
        scheduler.fire()

        XCTAssertEqual(events.count, 1, "no extra .up should fire while shortcut is still held")
    }

    func testFallbackTimerCancelledOnExplicitRelease() {
        let store = makeStore()
        let scheduler = FakeTimerScheduler()
        let engine = HotkeyEngine(store: store, timerScheduler: scheduler, currentFlags: { [] })

        engine.handleFlagsChanged([.function, .shift])
        engine.handleFlagsChanged([])

        XCTAssertEqual(scheduler.cancelCallCount, 1)
    }

    func testFallbackTimerCancelledOnCancel() {
        let store = makeStore()
        let scheduler = FakeTimerScheduler()
        let engine = HotkeyEngine(store: store, timerScheduler: scheduler, currentFlags: { [] })

        engine.handleFlagsChanged([.function, .shift])
        engine.handleKeyDown(keyCode: 53, flags: [])

        XCTAssertEqual(scheduler.cancelCallCount, 1)
    }

    // MARK: - stop() tears down active state

    func testStopCancelsFallbackTimer() {
        let store = makeStore()
        let scheduler = FakeTimerScheduler()
        let engine = HotkeyEngine(store: store, timerScheduler: scheduler, currentFlags: { [] })

        engine.handleFlagsChanged([.function, .shift])
        engine.stop()

        XCTAssertEqual(scheduler.cancelCallCount, 1)
    }
}
