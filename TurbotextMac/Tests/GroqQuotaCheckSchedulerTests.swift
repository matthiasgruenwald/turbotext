import XCTest
@testable import Turbotext

final class GroqQuotaCheckSchedulerTests: XCTestCase {

    func testChecksWhenGroqKeyPresentAndQuotaUnknown() {
        XCTAssertTrue(GroqQuotaCheckScheduler.shouldCheck(
            hasGroqKey: true,
            alwaysLocalTranscription: false,
            remainingAudioSeconds: nil,
            fallbackActive: false
        ))
    }

    func testSkipsWhenNoGroqKey() {
        XCTAssertFalse(GroqQuotaCheckScheduler.shouldCheck(
            hasGroqKey: false,
            alwaysLocalTranscription: false,
            remainingAudioSeconds: nil,
            fallbackActive: false
        ))
    }

    func testSkipsWhenAlwaysLocalTranscription() {
        XCTAssertFalse(GroqQuotaCheckScheduler.shouldCheck(
            hasGroqKey: true,
            alwaysLocalTranscription: true,
            remainingAudioSeconds: nil,
            fallbackActive: false
        ))
    }

    func testSkipsWhenQuotaAlreadyKnown() {
        XCTAssertFalse(GroqQuotaCheckScheduler.shouldCheck(
            hasGroqKey: true,
            alwaysLocalTranscription: false,
            remainingAudioSeconds: 600,
            fallbackActive: false
        ))
    }

    func testSkipsWhenFallbackAlreadyActive() {
        XCTAssertFalse(GroqQuotaCheckScheduler.shouldCheck(
            hasGroqKey: true,
            alwaysLocalTranscription: false,
            remainingAudioSeconds: nil,
            fallbackActive: true
        ))
    }
}
