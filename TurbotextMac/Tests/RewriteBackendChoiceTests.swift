import XCTest
@testable import Turbotext

final class RewriteBackendChoiceTests: XCTestCase {
    func testInitMapsAusIgnoringProviderMode() {
        XCTAssertEqual(RewriteBackendChoice(backend: .aus, providerMode: .groq), .aus)
        XCTAssertEqual(RewriteBackendChoice(backend: .aus, providerMode: .openAI), .aus)
    }

    func testInitMapsLokalIgnoringProviderMode() {
        XCTAssertEqual(RewriteBackendChoice(backend: .lokal, providerMode: .groq), .lokal)
        XCTAssertEqual(RewriteBackendChoice(backend: .lokal, providerMode: .openAI), .lokal)
    }

    func testInitMapsOnlineByProviderMode() {
        XCTAssertEqual(RewriteBackendChoice(backend: .online, providerMode: .groq), .groq)
        XCTAssertEqual(RewriteBackendChoice(backend: .online, providerMode: .openAI), .openAI)
    }

    func testBackendRoundTrip() {
        XCTAssertEqual(RewriteBackendChoice.aus.backend, .aus)
        XCTAssertEqual(RewriteBackendChoice.lokal.backend, .lokal)
        XCTAssertEqual(RewriteBackendChoice.groq.backend, .online)
        XCTAssertEqual(RewriteBackendChoice.openAI.backend, .online)
    }

    func testProviderModeOnlySetForOnlineChoices() {
        XCTAssertNil(RewriteBackendChoice.aus.providerMode)
        XCTAssertNil(RewriteBackendChoice.lokal.providerMode)
        XCTAssertEqual(RewriteBackendChoice.groq.providerMode, .groq)
        XCTAssertEqual(RewriteBackendChoice.openAI.providerMode, .openAI)
    }

    func testDisplayNames() {
        XCTAssertEqual(RewriteBackendChoice.aus.displayName, "Aus")
        XCTAssertEqual(RewriteBackendChoice.lokal.displayName, "Lokal")
        XCTAssertEqual(RewriteBackendChoice.groq.displayName, "Groq")
        XCTAssertEqual(RewriteBackendChoice.openAI.displayName, "OpenAI")
    }

    func testAllCasesOrderMatchesFourOptions() {
        XCTAssertEqual(RewriteBackendChoice.allCases, [.aus, .lokal, .groq, .openAI])
    }
}
