import XCTest
@testable import Turbotext

@MainActor
final class GroqQuotaStoreTests: XCTestCase {

    override func tearDown() {
        resetQuotaStore()
        super.tearDown()
    }

    private func resetQuotaStore() {
        let store = GroqQuotaStore.shared
        store.activateFallback(resetAt: Date().addingTimeInterval(-10))
        store.clearIfExpired()
    }

    func testUpdateWithResetAtSetsBothValues() {
        let resetAt = Date().addingTimeInterval(3600)
        GroqQuotaStore.shared.update(remainingSeconds: 120, resetAt: resetAt)
        XCTAssertEqual(GroqQuotaStore.shared.remainingAudioSeconds, 120)
        XCTAssertEqual(GroqQuotaStore.shared.rateLimitResetAt, resetAt)
    }

    func testUpdateWithoutResetAtKeepsPreviousResetAt() {
        let resetAt = Date().addingTimeInterval(3600)
        GroqQuotaStore.shared.update(remainingSeconds: 300, resetAt: resetAt)
        GroqQuotaStore.shared.update(remainingSeconds: 250, resetAt: nil)
        XCTAssertEqual(GroqQuotaStore.shared.remainingAudioSeconds, 250)
        XCTAssertEqual(GroqQuotaStore.shared.rateLimitResetAt, resetAt)
    }

    func testUpdateWithoutResetAtAndNoPriorResetAtLeavesItNil() {
        GroqQuotaStore.shared.update(remainingSeconds: 90, resetAt: nil)
        XCTAssertEqual(GroqQuotaStore.shared.remainingAudioSeconds, 90)
        XCTAssertNil(GroqQuotaStore.shared.rateLimitResetAt)
    }

    func testRecordUsageAccumulatesWithinSameDay() {
        let store = GroqQuotaStore.shared
        store.resetUsedToday()
        let noon = Date()
        store.recordUsage(seconds: 30, on: noon)
        store.recordUsage(seconds: 45, on: noon.addingTimeInterval(60))
        XCTAssertEqual(store.usedSecondsToday, 75)
    }

    func testRecordUsageResetsOnNewCalendarDay() {
        let store = GroqQuotaStore.shared
        store.resetUsedToday()
        let today = Date()
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!
        store.recordUsage(seconds: 100, on: today)
        store.recordUsage(seconds: 20, on: tomorrow)
        XCTAssertEqual(store.usedSecondsToday, 20)
    }

    func testFormattedUsedTodayNeverNil() {
        let store = GroqQuotaStore.shared
        store.resetUsedToday()
        XCTAssertEqual(store.formattedUsedToday, "0 Sek.")
    }
}
