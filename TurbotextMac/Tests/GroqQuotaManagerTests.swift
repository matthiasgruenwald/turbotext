import XCTest
@testable import Turbotext

@MainActor
final class GroqQuotaManagerTests: XCTestCase {

    func testUpdateSetsRemainingSeconds() {
        GroqQuotaManager.shared.update(remainingSeconds: 120)
        XCTAssertEqual(GroqQuotaManager.shared.remainingAudioSeconds, 120)
    }

    func testRecordUsageAccumulatesWithinSameDay() {
        let store = GroqQuotaManager.shared
        store.resetUsedToday()
        let noon = Date()
        store.recordUsage(seconds: 30, on: noon)
        store.recordUsage(seconds: 45, on: noon.addingTimeInterval(60))
        XCTAssertEqual(store.usedSecondsToday, 75)
    }

    func testRecordUsageResetsOnNewCalendarDay() {
        let store = GroqQuotaManager.shared
        store.resetUsedToday()
        let today = Date()
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!
        store.recordUsage(seconds: 100, on: today)
        store.recordUsage(seconds: 20, on: tomorrow)
        XCTAssertEqual(store.usedSecondsToday, 20)
    }

    func testFormattedUsedTodayNeverNil() {
        let store = GroqQuotaManager.shared
        store.resetUsedToday()
        XCTAssertEqual(store.formattedUsedToday, "0 Sek.")
    }
}
