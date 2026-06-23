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

// MARK: - TranscriptionFallbackResolver (#43)

final class TranscriptionFallbackResolverTests: XCTestCase {

    // MARK: Red + transcription + toggle on + model installed → local fallback

    func testRedTranscriptionToggleOnModelInstalledFallsBackToLocal() {
        let decision = TranscriptionFallbackResolver.resolve(
            for: .red,
            workflowType: .transcription,
            autoFallbackToLocalOnOffline: true,
            isLocalModelInstalled: true
        )
        XCTAssertEqual(decision.backend, .local)
        XCTAssertEqual(decision.soundKind, .localFallbackActive)
    }

    // MARK: Toggle off → unchanged #42 behavior

    func testRedTranscriptionToggleOffStaysRemoteWithWarningSound() {
        let decision = TranscriptionFallbackResolver.resolve(
            for: .red,
            workflowType: .transcription,
            autoFallbackToLocalOnOffline: false,
            isLocalModelInstalled: true
        )
        XCTAssertEqual(decision.backend, .remote)
        XCTAssertEqual(decision.soundKind, .networkUnavailable)
    }

    // MARK: Model not installed → unchanged #42 behavior even with toggle on

    func testRedTranscriptionToggleOnModelNotInstalledStaysRemoteWithWarningSound() {
        let decision = TranscriptionFallbackResolver.resolve(
            for: .red,
            workflowType: .transcription,
            autoFallbackToLocalOnOffline: true,
            isLocalModelInstalled: false
        )
        XCTAssertEqual(decision.backend, .remote)
        XCTAssertEqual(decision.soundKind, .networkUnavailable)
    }

    // MARK: Other cloud workflow types never trigger fallback, even with toggle on

    func testRedTextImproverToggleOnModelInstalledNeverFallsBack() {
        let decision = TranscriptionFallbackResolver.resolve(
            for: .red,
            workflowType: .textImprover,
            autoFallbackToLocalOnOffline: true,
            isLocalModelInstalled: true
        )
        XCTAssertEqual(decision.backend, .remote)
        XCTAssertEqual(decision.soundKind, .networkUnavailable)
    }

    func testRedDampfAblassenToggleOnModelInstalledNeverFallsBack() {
        let decision = TranscriptionFallbackResolver.resolve(
            for: .red,
            workflowType: .dampfAblassen,
            autoFallbackToLocalOnOffline: true,
            isLocalModelInstalled: true
        )
        XCTAssertEqual(decision.backend, .remote)
        XCTAssertEqual(decision.soundKind, .networkUnavailable)
    }

    func testRedEmojiTextToggleOnModelInstalledNeverFallsBack() {
        let decision = TranscriptionFallbackResolver.resolve(
            for: .red,
            workflowType: .emojiText,
            autoFallbackToLocalOnOffline: true,
            isLocalModelInstalled: true
        )
        XCTAssertEqual(decision.backend, .remote)
        XCTAssertEqual(decision.soundKind, .networkUnavailable)
    }

    // MARK: Non-red status never triggers fallback or sound

    func testGreenTranscriptionToggleOnModelInstalledNoSoundNoFallback() {
        let decision = TranscriptionFallbackResolver.resolve(
            for: .green,
            workflowType: .transcription,
            autoFallbackToLocalOnOffline: true,
            isLocalModelInstalled: true
        )
        XCTAssertEqual(decision.backend, .remote)
        XCTAssertNil(decision.soundKind)
    }

    func testYellowTranscriptionToggleOnModelInstalledNoSoundNoFallback() {
        let decision = TranscriptionFallbackResolver.resolve(
            for: .yellow,
            workflowType: .transcription,
            autoFallbackToLocalOnOffline: true,
            isLocalModelInstalled: true
        )
        XCTAssertEqual(decision.backend, .remote)
        XCTAssertNil(decision.soundKind)
    }

    // MARK: localTranscription is never eligible for fallback (already local)

    func testRedLocalTranscriptionNeverFallsBackOrPlaysSound() {
        let decision = TranscriptionFallbackResolver.resolve(
            for: .red,
            workflowType: .localTranscription,
            autoFallbackToLocalOnOffline: true,
            isLocalModelInstalled: true
        )
        XCTAssertEqual(decision.backend, .remote)
        XCTAssertNil(decision.soundKind)
    }
}
