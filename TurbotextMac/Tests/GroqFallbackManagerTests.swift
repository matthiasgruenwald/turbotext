import XCTest
@testable import Turbotext

@MainActor
final class GroqFallbackManagerTests: XCTestCase {

    func testStartsIdleWithoutPersistedState() {
        let manager = GroqFallbackManager(defaults: InMemoryPersistence())
        XCTAssertEqual(manager.state, .idle)
        XCTAssertFalse(manager.isActive)
        XCTAssertNil(manager.rateLimitResetAt)
    }

    func testReportRateLimitExceededActivatesFallback() {
        let manager = GroqFallbackManager(defaults: InMemoryPersistence())
        let resetAt = Date().addingTimeInterval(3600)

        manager.reportRateLimitExceeded(resetAt: resetAt)

        XCTAssertEqual(manager.state, .active(resetAt: resetAt))
        XCTAssertTrue(manager.isActive)
        XCTAssertEqual(manager.rateLimitResetAt, resetAt)
    }

    func testReportRateLimitExceededNotifiesStateChange() {
        let manager = GroqFallbackManager(defaults: InMemoryPersistence())
        var receivedStates: [Bool] = []
        manager.onStateChanged = { receivedStates.append($0) }

        manager.reportRateLimitExceeded(resetAt: Date().addingTimeInterval(3600))

        XCTAssertEqual(receivedStates, [true])
    }

    func testCheckIfExpiredClearsFallbackAfterResetDate() {
        let manager = GroqFallbackManager(defaults: InMemoryPersistence())
        manager.reportRateLimitExceeded(resetAt: Date().addingTimeInterval(-10))

        manager.checkIfExpired()

        XCTAssertEqual(manager.state, .expired)
        XCTAssertFalse(manager.isActive)
        XCTAssertNil(manager.rateLimitResetAt)
    }

    func testCheckIfExpiredKeepsActiveBeforeResetDate() {
        let manager = GroqFallbackManager(defaults: InMemoryPersistence())
        let resetAt = Date().addingTimeInterval(3600)
        manager.reportRateLimitExceeded(resetAt: resetAt)

        manager.checkIfExpired()

        XCTAssertTrue(manager.isActive)
        XCTAssertEqual(manager.rateLimitResetAt, resetAt)
    }

    func testCheckIfExpiredNotifiesStateChange() {
        let manager = GroqFallbackManager(defaults: InMemoryPersistence())
        manager.reportRateLimitExceeded(resetAt: Date().addingTimeInterval(-10))
        var receivedStates: [Bool] = []
        manager.onStateChanged = { receivedStates.append($0) }

        manager.checkIfExpired()

        XCTAssertEqual(receivedStates, [false])
    }

    func testPersistsFallbackActiveAcrossRestart() {
        let store = InMemoryPersistence()
        let resetAt = Date().addingTimeInterval(3600)
        let first = GroqFallbackManager(defaults: store)
        first.reportRateLimitExceeded(resetAt: resetAt)

        let second = GroqFallbackManager(defaults: store)

        XCTAssertTrue(second.isActive)
        XCTAssertEqual(second.rateLimitResetAt?.timeIntervalSince1970 ?? 0, resetAt.timeIntervalSince1970, accuracy: 0.001)
    }

    func testClearsExpiredFallbackOnRestartWhenResetDatePassed() {
        let store = InMemoryPersistence()
        let first = GroqFallbackManager(defaults: store)
        first.reportRateLimitExceeded(resetAt: Date().addingTimeInterval(-10))

        let second = GroqFallbackManager(defaults: store)

        XCTAssertFalse(second.isActive)
        XCTAssertNil(second.rateLimitResetAt)
    }
}
