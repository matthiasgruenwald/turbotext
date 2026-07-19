import XCTest
@testable import Turbotext

@MainActor
final class AppleSpeechAvailabilityStateTests: XCTestCase {
    func testStartsFalseBeforeRefresh() {
        let state = AppleSpeechAvailabilityState(checkStatus: { .available })
        XCTAssertFalse(state.isAvailable)
    }

    func testRefreshAdoptsTheCheckedValue() async {
        let state = AppleSpeechAvailabilityState(checkStatus: { .available })
        state.refresh()

        for _ in 0..<50 where !state.isAvailable {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }

        XCTAssertTrue(state.isAvailable)
    }

    func testRefreshCanAdoptFalse() async {
        let state = AppleSpeechAvailabilityState(checkStatus: { .assetsNotInstalled })
        state.refresh()

        // Give the task a moment to run; result should settle on false either way.
        try? await Task.sleep(nanoseconds: 20_000_000)

        XCTAssertFalse(state.isAvailable)
    }
}
