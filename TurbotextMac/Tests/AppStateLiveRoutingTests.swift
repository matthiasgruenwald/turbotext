import XCTest
@testable import Turbotext

@MainActor
final class AppStateLiveRoutingTests: XCTestCase {

    func testNonAppleSpeechResolutionsStayFileBased() {
        for resolution in [ResolvedTranscriptionBackend.remote, .whisperKit, .unavailable] {
            XCTAssertFalse(AppState.routesToLiveDictation(resolution))
        }
    }

    func testAppleSpeechResolutionRoutesLiveOnlyOnSupportedSystems() {
        if #available(macOS 26, *) {
            XCTAssertTrue(AppState.routesToLiveDictation(.appleSpeech))
        } else {
            XCTAssertFalse(AppState.routesToLiveDictation(.appleSpeech))
        }
    }
}
