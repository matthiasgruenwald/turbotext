import XCTest
@testable import Turbotext

final class ReasoningEffortTests: XCTestCase {
    func testReasoningModelCarriesEffortAndLunaName() {
        let model = RewriteModel.reasoning(.low)
        XCTAssertEqual(model.apiName, "gpt-6-luna")
        XCTAssertEqual(model.reasoningEffort, .low)
        XCTAssertNil(RewriteModel.fastEdit.reasoningEffort)
    }

    func testAppSettingsDefaultsEffortToMediumWhenMissing() throws {
        let data = Data(#"{"rewriteBackend":"online"}"#.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(settings.openAIReasoningEffort, .medium)
    }

    func testAppSettingsRoundTripsEffort() throws {
        var settings = AppSettings()
        settings.openAIReasoningEffort = .high
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(decoded.openAIReasoningEffort, .high)
    }
}
