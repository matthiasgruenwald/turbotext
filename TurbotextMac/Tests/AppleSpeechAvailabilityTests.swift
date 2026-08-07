import XCTest
@testable import Turbotext

@MainActor
final class AppleSpeechAvailabilityTests: XCTestCase {
    private func makeSignal() -> (AppLifecycleSignal, fire: () -> Void) {
        var handler: (() -> Void)?
        let signal = AppLifecycleSignal { newHandler in handler = newHandler }
        return (signal, { handler?() })
    }

    private func waitUntil(_ condition: @escaping () -> Bool) async {
        for _ in 0..<200 where !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    // MARK: - Launch secures assets

    func testLaunchReservesThenChecksStatus() async {
        var events: [String] = []
        let (signal, _) = makeSignal()
        let state = AppleSpeechAvailability(
            checkStatus: {
                events.append("status-check")
                return .available
            },
            reserveAssets: { events.append("reserve") },
            lifecycleSignal: signal
        )

        await waitUntil { events == ["reserve", "status-check"] }
        XCTAssertEqual(events, ["reserve", "status-check"])
        _ = state
    }

    // MARK: - Wake and activation trigger the same flow (fixes F3 from #188)

    func testWakeSignalTriggersTheSameSecuringFlowAsLaunch() async {
        var reserveCount = 0
        let (signal, fireWake) = makeSignal()
        let state = AppleSpeechAvailability(
            checkStatus: { .available },
            reserveAssets: { reserveCount += 1 },
            lifecycleSignal: signal
        )

        await waitUntil { reserveCount >= 1 }
        XCTAssertEqual(reserveCount, 1)

        fireWake()
        await waitUntil { reserveCount >= 2 }

        XCTAssertEqual(reserveCount, 2)
        XCTAssertEqual(state.status, .available)
    }

    func testReservationIsRenewedOnEveryTrigger() async {
        var reserveCount = 0
        let (signal, fireWake) = makeSignal()
        let state = AppleSpeechAvailability(
            checkStatus: { .available },
            reserveAssets: { reserveCount += 1 },
            lifecycleSignal: signal
        )
        await waitUntil { reserveCount >= 1 }

        fireWake()
        await waitUntil { reserveCount >= 2 }
        fireWake()
        await waitUntil { reserveCount >= 3 }

        XCTAssertEqual(reserveCount, 3)
        _ = state
    }

    // MARK: - Installation kicks off when assets are missing but installable

    func testTriggerStartsInstallationWhenAssetsAreMissingButInstallable() async {
        var installationRequested = false
        let (signal, fireWake) = makeSignal()
        let state = AppleSpeechAvailability(
            checkStatus: { .assetsNotInstalled },
            requestAssetInstallation: {
                installationRequested = true
                return .available
            },
            reserveAssets: {},
            lifecycleSignal: signal
        )

        fireWake()
        await waitUntil { state.status == .available }

        XCTAssertTrue(installationRequested)
        XCTAssertEqual(state.status, .available)
    }

    // MARK: - Permanently unsupported / below the OS floor never installs

    func testGermanAssetsUnsupportedNeverInstalls() async {
        var installationRequested = false
        let (signal, fireWake) = makeSignal()
        let state = AppleSpeechAvailability(
            checkStatus: { .germanAssetsUnsupported },
            requestAssetInstallation: {
                installationRequested = true
                return .available
            },
            reserveAssets: {},
            lifecycleSignal: signal
        )

        fireWake()
        await waitUntil { state.status == .germanAssetsUnsupported }
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertFalse(installationRequested)
    }

    func testBelowOSFloorNeverInstalls() async {
        var installationRequested = false
        let (signal, fireWake) = makeSignal()
        let state = AppleSpeechAvailability(
            checkStatus: { .unsupportedOS },
            requestAssetInstallation: {
                installationRequested = true
                return .available
            },
            reserveAssets: {},
            lifecycleSignal: signal
        )

        fireWake()
        await waitUntil { state.status == .unsupportedOS }
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertFalse(installationRequested)
    }

    // MARK: - Parallel triggers dedupe to a single running installation

    func testParallelTriggersProduceExactlyOneRunningInstallation() async {
        var installCallCount = 0
        let state = AppleSpeechAvailability(
            checkStatus: { .assetsNotInstalled },
            requestAssetInstallation: {
                installCallCount += 1
                try? await Task.sleep(for: .milliseconds(30))
                return .available
            },
            reserveAssets: {},
            lifecycleSignal: AppLifecycleSignal { _ in }
        )

        async let first: Void = state.ensureAssetsReady()
        async let second: Void = state.ensureAssetsReady()
        _ = await (first, second)

        XCTAssertEqual(installCallCount, 1)
        XCTAssertEqual(state.status, .available)
    }

    // MARK: - Successful installation reserves again, failed installation does not

    /// Construction itself triggers one launch securing pass, so both reserve tests pin
    /// `checkStatus` to `.available` for that first call (nothing to install, isolates the
    /// launch pass to a single reserve) and only switch to the exercised status from the
    /// explicit `ensureAssetsReady()` call the test actually measures.
    func testSuccessfulInstallationReservesAgain() async {
        var reserveCount = 0
        var checkCallCount = 0
        let state = AppleSpeechAvailability(
            checkStatus: {
                checkCallCount += 1
                return checkCallCount == 1 ? .available : .assetsNotInstalled
            },
            requestAssetInstallation: { .available },
            reserveAssets: { reserveCount += 1 },
            lifecycleSignal: AppLifecycleSignal { _ in }
        )
        await waitUntil { checkCallCount >= 1 }
        reserveCount = 0

        await state.ensureAssetsReady()

        // One reserve before the status recheck, one more after the successful install.
        XCTAssertEqual(reserveCount, 2)
        XCTAssertEqual(state.status, .available)
    }

    func testFailedInstallationDoesNotReserveAgain() async {
        var reserveCount = 0
        var checkCallCount = 0
        let state = AppleSpeechAvailability(
            checkStatus: {
                checkCallCount += 1
                return checkCallCount == 1 ? .available : .assetsNotInstalled
            },
            requestAssetInstallation: {
                throw AppleSpeechAssetInstallationError.requestUnavailable
            },
            reserveAssets: { reserveCount += 1 },
            lifecycleSignal: AppLifecycleSignal { _ in }
        )
        await waitUntil { checkCallCount >= 1 }
        reserveCount = 0

        await state.ensureAssetsReady()

        // The pre-check reserve still happens, but never a second one after a failed install.
        XCTAssertEqual(reserveCount, 1)
        XCTAssertEqual(
            state.assetInstallationErrorText,
            "Die Installation der Apple-Sprachassets ist fehlgeschlagen: Die Apple-Sprachassets können auf diesem Mac derzeit nicht zur Installation reserviert werden."
        )
        XCTAssertEqual(state.status, .assetsNotInstalled)
        XCTAssertFalse(state.isInstallingAssets)
    }

    // MARK: - Synchronous readiness query

    func testReadinessReflectsAvailableStatus() async {
        let state = AppleSpeechAvailability(
            checkStatus: { .available },
            reserveAssets: {},
            lifecycleSignal: AppLifecycleSignal { _ in }
        )
        await state.ensureAssetsReady()

        XCTAssertEqual(state.readiness, .ready)
    }

    func testReadinessReportsReasonAndInstallabilityWhenNotReady() async {
        let state = AppleSpeechAvailability(
            checkStatus: { .germanAssetsUnsupported },
            reserveAssets: {},
            lifecycleSignal: AppLifecycleSignal { _ in }
        )
        await state.ensureAssetsReady()

        XCTAssertEqual(state.readiness, .notReady(reason: .germanAssetsUnsupported, canInstall: false))
    }
}
