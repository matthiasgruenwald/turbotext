import XCTest
@testable import Turbotext

/// Fake consent coordinator — `SpokenRewriteWorkflow`'s rewrite closures capture it, but
/// these tests never actually run a rewrite, so every method is unreachable.
@MainActor
private final class FakeRewriteConsentCoordinator: RewriteConsentCoordinating {
    func presentConsent(reason: RewriteConsentReason, provider: OnlineProvider) async -> RewriteRouter.ConsentDecision {
        .insertRawText
    }
    func readConsent(_ workflow: WorkflowType) -> OnlineProvider? { nil }
    func writeConsent(_ workflow: WorkflowType, _ provider: OnlineProvider?) {}
}

/// Covers `WorkflowFactory.build` directly (#192): the four spoken-workflow types
/// (Transkription, Turbotext+, Dampf ablassen, Emoji-Text) now share one branch, so these
/// tests exercise that branch's data-driven differences instead of four near-duplicate
/// code paths. `WorkflowFactory` needs no `AppState` to construct (#191), so everything
/// here is a plain fake.
@MainActor
final class WorkflowFactoryBuildTests: XCTestCase {

    private let spokenTypes: [WorkflowType] = [.transcription, .textImprover, .dampfAblassen, .emojiText]

    private func makeFactory(
        resolution: @escaping (TranscriptionBackend?) -> WorkflowFactory.ResolvedTranscriber,
        resolveCallCount: Box<Int> = Box(0),
        capturedBackendOverrides: Box<[TranscriptionBackend?]> = Box([])
    ) -> (factory: WorkflowFactory, resolveCallCount: Box<Int>, capturedBackendOverrides: Box<[TranscriptionBackend?]>) {
        let factory = WorkflowFactory(
            resolveTranscriber: { backendOverride in
                resolveCallCount.value += 1
                capturedBackendOverrides.value.append(backendOverride)
                return resolution(backendOverride)
            },
            localTranscriber: { { _, _, _, _ in "local" } },
            rewriteConsentCoordinator: FakeRewriteConsentCoordinator(),
            secureAppleSpeechAssetsOnDemand: {},
            onLiveTranscriptUpdate: { _ in },
            onBergung: { _ in },
            rewriteProcessingLabel: { nil }
        )
        return (factory, resolveCallCount, capturedBackendOverrides)
    }

    private func settings(liveSmoothingBackend: LiveSmoothingBackend = .off) -> WorkflowFactory.Settings {
        var transcriptionSettings = TranscriptionSettings()
        transcriptionSettings.liveSmoothingBackend = liveSmoothingBackend
        return WorkflowFactory.Settings(
            appSettings: AppSettings(),
            transcriptionSettings: transcriptionSettings,
            textImprovementSettings: TextImprovementSettings(),
            dampfAblassenSettings: DampfAblassenSettings(),
            emojiTextSettings: EmojiTextSettings()
        )
    }

    private func remoteResolution(_ backendOverride: TranscriptionBackend?) -> WorkflowFactory.ResolvedTranscriber {
        WorkflowFactory.ResolvedTranscriber(
            transcriber: { _, _, _, _ in "remote" },
            backend: .remote,
            resolution: .remote,
            unavailableRejection: nil
        )
    }

    private func appleSpeechResolution(_ backendOverride: TranscriptionBackend?) -> WorkflowFactory.ResolvedTranscriber {
        WorkflowFactory.ResolvedTranscriber(
            transcriber: { _, _, _, _ in "apple" },
            backend: .local,
            resolution: .appleSpeech,
            unavailableRejection: nil
        )
    }

    private func unavailableResolution(rejection: WorkflowStartRejection) -> (TranscriptionBackend?) -> WorkflowFactory.ResolvedTranscriber {
        { _ in
            WorkflowFactory.ResolvedTranscriber(
                transcriber: nil,
                backend: .local,
                resolution: .unavailable,
                unavailableRejection: rejection
            )
        }
    }

    // MARK: - Unavailable resolution -> rejection, not a workflow (#192, fixes F2 from #188)

    func testUnavailableResolutionRejectsInsteadOfBuildingForAllFourSpokenTypes() {
        let rejection = WorkflowStartRejection(
            reason: "appleSpeech.assetsNotInstalled",
            message: "Sprachassets werden installiert – bitte gleich erneut versuchen.",
            canRetryImmediately: true
        )
        for type in spokenTypes {
            let (factory, _, _) = makeFactory(resolution: unavailableResolution(rejection: rejection))

            let result = factory.build(type, backendOverride: nil, settings: settings())

            guard case .rejected(let actual) = result else {
                XCTFail("expected .rejected for \(type), got \(result)")
                continue
            }
            XCTAssertEqual(actual, rejection, "rejection must pass through unchanged for \(type)")
        }
    }

    // MARK: - Transcriber resolution applied exactly once per build call (#192)

    func testResolveTranscriberIsCalledExactlyOnceForEachSpokenType() {
        for type in spokenTypes {
            let (factory, callCount, _) = makeFactory(resolution: remoteResolution)

            _ = factory.build(type, backendOverride: nil, settings: settings())

            XCTAssertEqual(callCount.value, 1, "resolveTranscriber must run exactly once for \(type)")
        }
    }

    func testLocalTranscriptionNeverCallsResolveTranscriber() {
        let (factory, callCount, _) = makeFactory(resolution: remoteResolution)

        _ = factory.build(.localTranscription, backendOverride: nil, settings: settings())

        XCTAssertEqual(callCount.value, 0)
    }

    // MARK: - Backend override only forwarded for plain transcription (pre-existing rule, preserved by #192)

    func testBackendOverrideIsOnlyForwardedForPlainTranscription() {
        for type in spokenTypes {
            let (factory, _, capturedOverrides) = makeFactory(resolution: remoteResolution)

            _ = factory.build(type, backendOverride: .local, settings: settings())

            let expected: TranscriptionBackend? = type == .transcription ? .local : nil
            XCTAssertEqual(capturedOverrides.value, [expected], "backendOverride forwarding for \(type)")
        }
    }

    // MARK: - File-based vs. live routing (#192: every type follows the same live rule)

    func testRemoteResolutionBuildsFileBasedWorkflowForAllFourSpokenTypes() {
        for type in spokenTypes {
            let (factory, _, _) = makeFactory(resolution: remoteResolution)

            let result = factory.build(type, backendOverride: nil, settings: settings())

            guard case .workflow(let workflow) = result else {
                XCTFail("expected .workflow for \(type)")
                continue
            }
            XCTAssertEqual(workflow.type, type)
            if type == .transcription {
                XCTAssertTrue(workflow is TranscriptionWorkflow, "\(type) should build a file-based TranscriptionWorkflow")
            } else {
                XCTAssertTrue(workflow is SpokenRewriteWorkflow, "\(type) should build a file-based SpokenRewriteWorkflow")
            }
        }
    }

    func testAppleSpeechResolutionBuildsLiveDictationWorkflowForAllFourSpokenTypes() throws {
        try XCTSkipUnless({ if #available(macOS 26, *) { return true }; return false }())
        guard #available(macOS 26, *) else { return }

        for type in spokenTypes {
            let (factory, _, _) = makeFactory(resolution: appleSpeechResolution)

            let result = factory.build(type, backendOverride: nil, settings: settings())

            guard case .workflow(let workflow) = result else {
                XCTFail("expected .workflow for \(type)")
                continue
            }
            XCTAssertTrue(workflow is LiveDictationWorkflow, "\(type) should route live when Apple Speech resolves")
            XCTAssertEqual(workflow.type, type)
        }
    }

    // MARK: - Local transcription always builds, never rejects via resolveTranscriber

    func testLocalTranscriptionAlwaysBuildsAWorkflow() {
        let (factory, _, _) = makeFactory(resolution: remoteResolution)

        let result = factory.build(.localTranscription, backendOverride: nil, settings: settings())

        guard case .workflow(let workflow) = result else {
            return XCTFail("expected .workflow for .localTranscription")
        }
        XCTAssertTrue(workflow is TranscriptionWorkflow)
        XCTAssertEqual(workflow.type, .localTranscription)
    }
}

/// Tiny reference box so closures can mutate a shared counter/log without `inout`.
final class Box<Value> {
    var value: Value
    init(_ value: Value) { self.value = value }
}
