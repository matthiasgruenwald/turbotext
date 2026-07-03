import XCTest
@testable import Turbotext

@MainActor
final class PrewarmObserverTests: XCTestCase {

    func testHandleSettingsChangeTriggersPrewarm() {
        var prewarmCallCount = 0
        let observer = PrewarmObserver(prewarm: { prewarmCallCount += 1 })

        var old = AppSettings()
        var new = AppSettings()
        new.secureLocalModeEnabled = true

        observer.handleSettingsChange(old: old, new: new)

        XCTAssertEqual(prewarmCallCount, 1)
    }

    func testHandleSettingsChangeTriggersPrewarmEvenWithoutSecureLocalModeChange() {
        var prewarmCallCount = 0
        let observer = PrewarmObserver(prewarm: { prewarmCallCount += 1 })

        let old = AppSettings()
        var new = AppSettings()
        new.hasSeenOnboarding = true

        observer.handleSettingsChange(old: old, new: new)

        XCTAssertEqual(prewarmCallCount, 1)
    }
}
