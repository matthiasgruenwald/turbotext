import XCTest
import AppKit
@testable import Turbotext

final class WorkflowShortcutHintTests: XCTestCase {

    func testNoWarningWhenInputMonitoringGranted() {
        let shortcuts = [Shortcut(modifiers: [], keyCode: 96)]
        let needsWarning = WorkflowShortcutHint.needsInputMonitoringWarning(
            shortcuts: shortcuts,
            inputMonitoringGranted: true
        )
        XCTAssertFalse(needsWarning)
    }

    func testNoWarningWhenOnlyModifierShortcuts() {
        let shortcuts = [Shortcut(modifiers: [.function, .shift], keyCode: nil)]
        let needsWarning = WorkflowShortcutHint.needsInputMonitoringWarning(
            shortcuts: shortcuts,
            inputMonitoringGranted: false
        )
        XCTAssertFalse(needsWarning)
    }

    func testWarnsWhenKeyCodeShortcutAndPermissionMissing() {
        let shortcuts = [Shortcut(modifiers: [], keyCode: 96)]
        let needsWarning = WorkflowShortcutHint.needsInputMonitoringWarning(
            shortcuts: shortcuts,
            inputMonitoringGranted: false
        )
        XCTAssertTrue(needsWarning)
    }

    func testWarnsWhenMixedShortcutsIncludeKeyCodeAndPermissionMissing() {
        let shortcuts = [
            Shortcut(modifiers: [.function, .shift], keyCode: nil),
            Shortcut(modifiers: [.control], keyCode: 96)
        ]
        let needsWarning = WorkflowShortcutHint.needsInputMonitoringWarning(
            shortcuts: shortcuts,
            inputMonitoringGranted: false
        )
        XCTAssertTrue(needsWarning)
    }

    func testNoWarningWhenNoShortcuts() {
        let needsWarning = WorkflowShortcutHint.needsInputMonitoringWarning(
            shortcuts: [],
            inputMonitoringGranted: false
        )
        XCTAssertFalse(needsWarning)
    }
}
