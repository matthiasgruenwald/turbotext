import XCTest
@testable import Turbotext

final class OfflineWarningSoundDecisionTests: XCTestCase {

    // MARK: - Red status, cloud workflows → sound

    func testRedStatusWithTranscriptionPlaysWarningSound() {
        let kind = OfflineWarningSoundDecision.kind(for: .red, workflowType: .transcription)
        XCTAssertEqual(kind, .networkUnavailable)
    }

    func testRedStatusWithTextImproverPlaysWarningSound() {
        let kind = OfflineWarningSoundDecision.kind(for: .red, workflowType: .textImprover)
        XCTAssertEqual(kind, .networkUnavailable)
    }

    func testRedStatusWithDampfAblassenPlaysWarningSound() {
        let kind = OfflineWarningSoundDecision.kind(for: .red, workflowType: .dampfAblassen)
        XCTAssertEqual(kind, .networkUnavailable)
    }

    func testRedStatusWithEmojiTextPlaysWarningSound() {
        let kind = OfflineWarningSoundDecision.kind(for: .red, workflowType: .emojiText)
        XCTAssertEqual(kind, .networkUnavailable)
    }

    // MARK: - localTranscription never triggers, regardless of status

    func testRedStatusWithLocalTranscriptionNeverPlaysSound() {
        let kind = OfflineWarningSoundDecision.kind(for: .red, workflowType: .localTranscription)
        XCTAssertNil(kind)
    }

    func testGreenStatusWithLocalTranscriptionNeverPlaysSound() {
        let kind = OfflineWarningSoundDecision.kind(for: .green, workflowType: .localTranscription)
        XCTAssertNil(kind)
    }

    // MARK: - Yellow/green status never triggers

    func testYellowStatusWithTranscriptionPlaysNoSound() {
        let kind = OfflineWarningSoundDecision.kind(for: .yellow, workflowType: .transcription)
        XCTAssertNil(kind)
    }

    func testGreenStatusWithTranscriptionPlaysNoSound() {
        let kind = OfflineWarningSoundDecision.kind(for: .green, workflowType: .transcription)
        XCTAssertNil(kind)
    }

    func testYellowStatusWithTextImproverPlaysNoSound() {
        let kind = OfflineWarningSoundDecision.kind(for: .yellow, workflowType: .textImprover)
        XCTAssertNil(kind)
    }
}
