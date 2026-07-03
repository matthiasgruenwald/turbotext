import XCTest
@testable import Turbotext

@MainActor
final class DockModeObserverTests: XCTestCase {

    func testHandleSettingsChangeAppliesWhenDockModeChanges() {
        var appliedValues: [Bool] = []
        let observer = DockModeObserver(apply: { appliedValues.append($0) })

        var old = AppSettings()
        old.dockModeEnabled = true
        var new = AppSettings()
        new.dockModeEnabled = false

        observer.handleSettingsChange(old: old, new: new)

        XCTAssertEqual(appliedValues, [false])
    }

    func testHandleSettingsChangeDoesNotApplyWhenDockModeUnchanged() {
        var appliedValues: [Bool] = []
        let observer = DockModeObserver(apply: { appliedValues.append($0) })

        var old = AppSettings()
        old.hasSeenOnboarding = false
        var new = AppSettings()
        new.hasSeenOnboarding = true

        observer.handleSettingsChange(old: old, new: new)

        XCTAssertTrue(appliedValues.isEmpty)
    }
}
