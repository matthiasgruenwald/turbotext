import XCTest
@testable import Turbotext

/// Live-routing predicate test moved from `AppStateLiveRoutingTests` (#191): the
/// predicate now lives on `WorkflowFactory`, which — unlike `AppState` — needs no
/// app-state seam to construct, so this test needs no fixture beyond the type itself.
@MainActor
final class WorkflowFactoryLiveRoutingTests: XCTestCase {

    func testNonAppleSpeechResolutionsStayFileBased() {
        for resolution in [ResolvedTranscriptionBackend.remote, .whisperKit, .unavailable] {
            XCTAssertFalse(WorkflowFactory.routesToLiveDictation(resolution))
        }
    }

    func testAppleSpeechResolutionRoutesLiveOnlyOnSupportedSystems() {
        if #available(macOS 26, *) {
            XCTAssertTrue(WorkflowFactory.routesToLiveDictation(.appleSpeech))
        } else {
            XCTAssertFalse(WorkflowFactory.routesToLiveDictation(.appleSpeech))
        }
    }
}
