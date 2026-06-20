import XCTest
@testable import Turbotext

final class GroqQuotaCheckSchedulerTests: XCTestCase {

    func testChecksWhenGroqKeyPresentAndQuotaUnknown() {
        XCTAssertTrue(GroqQuotaCheckScheduler.shouldCheck(
            hasGroqKey: true,
            secureLocalModeEnabled: false,
            remainingAudioSeconds: nil,
            fallbackActive: false
        ))
    }

    func testSkipsWhenNoGroqKey() {
        XCTAssertFalse(GroqQuotaCheckScheduler.shouldCheck(
            hasGroqKey: false,
            secureLocalModeEnabled: false,
            remainingAudioSeconds: nil,
            fallbackActive: false
        ))
    }

    func testSkipsWhenSecureLocalModeEnabled() {
        XCTAssertFalse(GroqQuotaCheckScheduler.shouldCheck(
            hasGroqKey: true,
            secureLocalModeEnabled: true,
            remainingAudioSeconds: nil,
            fallbackActive: false
        ))
    }

    func testSkipsWhenQuotaAlreadyKnown() {
        XCTAssertFalse(GroqQuotaCheckScheduler.shouldCheck(
            hasGroqKey: true,
            secureLocalModeEnabled: false,
            remainingAudioSeconds: 600,
            fallbackActive: false
        ))
    }

    func testSkipsWhenFallbackAlreadyActive() {
        XCTAssertFalse(GroqQuotaCheckScheduler.shouldCheck(
            hasGroqKey: true,
            secureLocalModeEnabled: false,
            remainingAudioSeconds: nil,
            fallbackActive: true
        ))
    }
}
