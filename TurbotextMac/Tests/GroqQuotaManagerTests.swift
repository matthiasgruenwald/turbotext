import XCTest
@testable import Turbotext

@MainActor
final class GroqQuotaManagerTests: XCTestCase {

    func testUpdateWithResetAtSetsBothValues() {
        let resetAt = Date().addingTimeInterval(3600)
        GroqQuotaManager.shared.update(remainingSeconds: 120, resetAt: resetAt)
        XCTAssertEqual(GroqQuotaManager.shared.remainingAudioSeconds, 120)
        XCTAssertEqual(GroqQuotaManager.shared.rateLimitResetAt, resetAt)
    }

    func testUpdateWithoutResetAtKeepsPreviousResetAt() {
        let resetAt = Date().addingTimeInterval(3600)
        GroqQuotaManager.shared.update(remainingSeconds: 300, resetAt: resetAt)
        GroqQuotaManager.shared.update(remainingSeconds: 250, resetAt: nil)
        XCTAssertEqual(GroqQuotaManager.shared.remainingAudioSeconds, 250)
        XCTAssertEqual(GroqQuotaManager.shared.rateLimitResetAt, resetAt)
    }

    func testUpdateWithoutResetAtAndNoPriorResetAtLeavesItNil() {
        GroqQuotaManager.shared.update(remainingSeconds: 90, resetAt: nil)
        XCTAssertEqual(GroqQuotaManager.shared.remainingAudioSeconds, 90)
        XCTAssertNil(GroqQuotaManager.shared.rateLimitResetAt)
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
