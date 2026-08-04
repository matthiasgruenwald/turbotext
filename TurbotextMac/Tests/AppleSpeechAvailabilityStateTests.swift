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
            },
            reserveAssets: {}
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
            },
            reserveAssets: {}
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

    // MARK: - Sprachasset-Sicherstellung (#178)

    func testLaunchSecuringReservesAssetsBeforeCheckingStatus() async {
        var events: [String] = []
        let state = AppleSpeechAvailabilityState(
            checkStatus: {
                events.append("status-check")
                return .available
            },
            reserveAssets: { events.append("reserve") }
        )

        state.secureAssetsAtLaunch()

        for _ in 0..<50 where state.status != .available {
            try? await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(events, ["reserve", "status-check"])
        XCTAssertEqual(state.status, .available)
    }

    func testLaunchSecuringStartsInstallationWhenAssetsAreStillMissing() async {
        var installationRequested = false
        let state = AppleSpeechAvailabilityState(
            checkStatus: { .assetsNotInstalled },
            requestAssetInstallation: {
                installationRequested = true
                return .available
            },
            reserveAssets: {}
        )

        state.secureAssetsAtLaunch()

        for _ in 0..<50 where state.status != .available {
            try? await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertTrue(installationRequested)
        XCTAssertEqual(state.status, .available)
    }

    func testLaunchSecuringSkipsInstallationWhenAssetsAreAvailable() async {
        var installationRequested = false
        let state = AppleSpeechAvailabilityState(
            checkStatus: { .available },
            requestAssetInstallation: {
                installationRequested = true
                return .available
            },
            reserveAssets: {}
        )

        state.secureAssetsAtLaunch()

        for _ in 0..<50 where state.status != .available {
            try? await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertFalse(installationRequested)
    }

    func testLaunchSecuringDoesNotInstallWhenGermanAssetsAreUnsupported() async {
        var installationRequested = false
        let state = AppleSpeechAvailabilityState(
            checkStatus: { .germanAssetsUnsupported },
            requestAssetInstallation: {
                installationRequested = true
                return .available
            },
            reserveAssets: {}
        )

        state.secureAssetsAtLaunch()

        for _ in 0..<50 where state.status != .germanAssetsUnsupported {
            try? await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertFalse(installationRequested)
    }

    func testOnDemandSecuringRefreshesStatusBeforeInstallation() async {
        var installationRequested = false
        let state = AppleSpeechAvailabilityState(
            checkStatus: { .assetsNotInstalled },
            requestAssetInstallation: {
                installationRequested = true
                return .available
            },
            reserveAssets: {}
        )

        state.secureAssetsOnDemand()

        for _ in 0..<50 where state.status != .available {
            try? await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertTrue(installationRequested)
    }

    func testSuccessfulInstallationReservesAssetsAgain() async {
        var reserveCount = 0
        let state = AppleSpeechAvailabilityState(
            checkStatus: { .assetsNotInstalled },
            requestAssetInstallation: { .available },
            reserveAssets: { reserveCount += 1 }
        )

        state.installAssets()

        for _ in 0..<50 where reserveCount < 1 {
            try? await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(reserveCount, 1)
        XCTAssertEqual(state.status, .available)
    }

    func testFailedInstallationDoesNotReserveAssets() async {
        var reserveCount = 0
        let state = AppleSpeechAvailabilityState(
            checkStatus: { .assetsNotInstalled },
            requestAssetInstallation: {
                throw AppleSpeechAssetInstallationError.requestUnavailable
            },
            reserveAssets: { reserveCount += 1 }
        )

        state.installAssets()

        for _ in 0..<50 where state.isInstallingAssets || state.assetInstallationErrorText == nil {
            try? await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(reserveCount, 0)
    }
}
