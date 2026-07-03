import XCTest
import AppKit
@testable import Turbotext

/// Fake monitor installer: captures the handlers `HotkeyCaptureService` registers
/// instead of installing real `NSEvent` global/local monitors, so tests can drive
/// the full down -> engine -> trigger path deterministically without needing
/// Input Monitoring permission or real system events.
private final class FakeMonitorInstaller: HotkeyMonitorInstalling {
    private(set) var installCallCount = 0
    private(set) var removeCallCount = 0

    private var flagsHandler: ((NSEvent.ModifierFlags) -> Void)?
    private var keyDownHandler: ((UInt16, NSEvent.ModifierFlags) -> Void)?
    private var keyUpHandler: ((UInt16, NSEvent.ModifierFlags) -> Void)?

    func install(
        onFlagsChanged: @escaping (NSEvent.ModifierFlags) -> Void,
        onKeyDown: @escaping (UInt16, NSEvent.ModifierFlags) -> Void,
        onKeyUp: @escaping (UInt16, NSEvent.ModifierFlags) -> Void
    ) -> HotkeyMonitorToken {
        installCallCount += 1
        flagsHandler = onFlagsChanged
        keyDownHandler = onKeyDown
        keyUpHandler = onKeyUp
        return HotkeyMonitorToken { [weak self] in self?.removeCallCount += 1 }
    }

    func sendFlagsChanged(_ flags: NSEvent.ModifierFlags) {
        flagsHandler?(flags)
    }

    func sendKeyDown(keyCode: UInt16, flags: NSEvent.ModifierFlags) {
        keyDownHandler?(keyCode, flags)
    }

    func sendKeyUp(keyCode: UInt16, flags: NSEvent.ModifierFlags) {
        keyUpHandler?(keyCode, flags)
    }
}

private final class FakePermissionRequester: HotkeyPermissionRequesting {
    private(set) var requestCallCount = 0

    func requestListenEventAccess() {
        requestCallCount += 1
    }
}

@MainActor
final class HotkeyCaptureServiceTests: XCTestCase {

    private func makeStore() -> ShortcutStore {
        ShortcutStore(userDefaultsKey: "test_\(UUID().uuidString)")
    }

    private func makeService(
        store: ShortcutStore,
        installer: FakeMonitorInstaller? = nil,
        permissionRequester: FakePermissionRequester? = nil
    ) -> HotkeyCaptureService {
        HotkeyCaptureService(
            store: store,
            monitorInstaller: installer ?? FakeMonitorInstaller(),
            permissionRequester: permissionRequester ?? FakePermissionRequester()
        )
    }

    // MARK: - start() wires permission check + monitors

    func testStartRequestsInputMonitoringPermission() {
        let permissionRequester = FakePermissionRequester()
        let service = makeService(store: makeStore(), permissionRequester: permissionRequester)

        service.start()

        XCTAssertEqual(permissionRequester.requestCallCount, 1)
    }

    func testStartInstallsMonitorsExactlyOnce() {
        let installer = FakeMonitorInstaller()
        let service = makeService(store: makeStore(), installer: installer)

        service.start()

        XCTAssertEqual(installer.installCallCount, 1)
    }

    func testStopRemovesMonitors() {
        let installer = FakeMonitorInstaller()
        let service = makeService(store: makeStore(), installer: installer)

        service.start()
        service.stop()

        XCTAssertEqual(installer.removeCallCount, 1)
    }

    // MARK: - Public interface emits WorkflowType triggers, not raw down/up events

    func testFlagsChangedMatchingShortcutEmitsActivateWithWorkflowType() {
        let installer = FakeMonitorInstaller()
        let service = makeService(store: makeStore(), installer: installer)
        var triggers: [HotkeyTrigger] = []
        service.onTrigger = { triggers.append($0) }

        service.start()
        installer.sendFlagsChanged([.function, .shift])

        XCTAssertEqual(triggers.count, 1)
        guard case .activate(.transcription) = triggers[0] else { return XCTFail("expected activate(.transcription)") }
    }

    func testFlagsReleasedEmitsDeactivate() {
        let installer = FakeMonitorInstaller()
        let service = makeService(store: makeStore(), installer: installer)
        var triggers: [HotkeyTrigger] = []
        service.onTrigger = { triggers.append($0) }

        service.start()
        installer.sendFlagsChanged([.function, .shift])
        installer.sendFlagsChanged([])

        XCTAssertEqual(triggers.count, 2)
        guard case .deactivate(.transcription) = triggers[1] else { return XCTFail("expected deactivate(.transcription)") }
    }

    func testKeyDownMatchingFKeyShortcutEmitsActivate() {
        let store = makeStore()
        store.add(Shortcut(modifiers: [], keyCode: 96), for: .transcription)
        let installer = FakeMonitorInstaller()
        let service = makeService(store: store, installer: installer)
        var triggers: [HotkeyTrigger] = []
        service.onTrigger = { triggers.append($0) }

        service.start()
        installer.sendKeyDown(keyCode: 96, flags: [])

        guard case .activate(.transcription) = triggers.first else { return XCTFail("expected activate") }
    }

    func testKeyUpMatchingActiveFKeyComboEmitsDeactivate() {
        let store = makeStore()
        store.add(Shortcut(modifiers: [], keyCode: 96), for: .transcription)
        let installer = FakeMonitorInstaller()
        let service = makeService(store: store, installer: installer)
        var triggers: [HotkeyTrigger] = []
        service.onTrigger = { triggers.append($0) }

        service.start()
        installer.sendKeyDown(keyCode: 96, flags: [])
        installer.sendKeyUp(keyCode: 96, flags: [])

        guard case .deactivate(.transcription) = triggers.last else { return XCTFail("expected deactivate") }
        XCTAssertEqual(triggers.count, 2)
    }

    func testEscapeKeyDownEmitsCancelActive() {
        let installer = FakeMonitorInstaller()
        let service = makeService(store: makeStore(), installer: installer)
        var triggers: [HotkeyTrigger] = []
        service.onTrigger = { triggers.append($0) }

        service.start()
        installer.sendKeyDown(keyCode: 53, flags: [])

        guard case .cancelActive = triggers.first else { return XCTFail("expected cancelActive") }
    }

    // MARK: - Multi-shortcut arrays per workflow still work

    func testSecondShortcutAddedToSameWorkflowAlsoTriggers() {
        let store = makeStore()
        store.add(Shortcut(modifiers: [.control, .shift], keyCode: nil), for: .transcription)
        let installer = FakeMonitorInstaller()
        let service = makeService(store: store, installer: installer)
        var triggers: [HotkeyTrigger] = []
        service.onTrigger = { triggers.append($0) }

        service.start()
        installer.sendFlagsChanged([.control, .shift])

        guard case .activate(.transcription) = triggers.first else { return XCTFail("expected activate(.transcription)") }
    }
}
