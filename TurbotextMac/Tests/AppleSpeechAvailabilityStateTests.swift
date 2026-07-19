import XCTest
import Speech
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

    @available(macOS 26, *)
    func testSupportedAssetsBecomeAvailableAfterInstallationRequest() async {
        var didRequestInstallation = false
        var assetStatus: AssetInventory.Status = .supported
        let state = AppleSpeechAvailabilityState(
            checkStatus: { .assetsNotInstalled },
            requestAssetInstallation: {
                didRequestInstallation = true
                XCTAssertEqual(assetStatus, .supported)
                assetStatus = .installed
                return AppleSpeechTranscriptionService.availabilityStatus(
                    osSupportsAppleSpeech: true,
                    assetStatus: assetStatus
                )
            }
        )

        state.installAssets()

        for _ in 0..<50 where !state.isAvailable {
            try? await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertTrue(didRequestInstallation)
        XCTAssertEqual(state.status, .available)
        XCTAssertFalse(state.isInstallingAssets)
        XCTAssertNil(state.assetInstallationErrorText)
    }

    func testInstallShowsReadableErrorWhenAppleCannotReserveAssets() async {
        let state = AppleSpeechAvailabilityState(
            checkStatus: { .assetsNotInstalled },
            requestAssetInstallation: {
                throw AppleSpeechAssetInstallationError.requestUnavailable
            }
        )

        state.installAssets()

        for _ in 0..<50 where state.isInstallingAssets || state.assetInstallationErrorText == nil {
            try? await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(
            state.assetInstallationErrorText,
            "Die Installation der Apple-Sprachassets ist fehlgeschlagen: Die Apple-Sprachassets können auf diesem Mac derzeit nicht zur Installation reserviert werden."
        )
        XCTAssertEqual(state.status, .assetsNotInstalled)
    }
}
