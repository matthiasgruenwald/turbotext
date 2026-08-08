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

    // MARK: - A hung install request must not permanently wedge retries (#191 follow-up)

    /// Reproduces the standby report: if `downloadAndInstall()` never returns (e.g. the
    /// system suspended the request during sleep), `installTask` never clears, so every
    /// later retry — user-pressed or wake-triggered — just re-awaits the same dead task
    /// forever instead of starting a fresh install attempt.
    func testHungInstallRequestEventuallyClearsAndAllowsAFreshRetry() async {
        var installCallCount = 0
        let (signal, fireWake) = makeSignal()
        let state = AppleSpeechAvailability(
            checkStatus: { .assetsNotInstalled },
            requestAssetInstallation: {
                installCallCount += 1
                try? await Task.sleep(for: .seconds(3_600))
                return .available
            },
            reserveAssets: {},
            lifecycleSignal: signal,
            installDeadline: .milliseconds(50)
        )

        await waitUntil { installCallCount >= 1 }
        XCTAssertTrue(state.isInstallingAssets)

        // The deadline should fire on its own, well before any real standby-length hang,
        // clearing the wedge without needing an app restart.
        await waitUntil { !state.isInstallingAssets }
        XCTAssertNotNil(state.assetInstallationErrorText)

        // A later retry — user-pressed or wake-triggered — must start a genuinely new
        // install attempt rather than being permanently blocked by the dead one.
        fireWake()
        await waitUntil { installCallCount >= 2 }
        XCTAssertEqual(installCallCount, 2)
    }

    /// The status check is not the only Speech-framework call that can wedge across
    /// standby — `reserve` can too, since it goes through the same XPC-backed asset
    /// daemon. Without its own deadline, a hung `reserveAssets()` blocks `checkStatus`
    /// and `performInstall` from ever running, and every later trigger just re-hangs
    /// on a fresh un-bounded reserve call again.
    func testHungReserveCallDoesNotBlockTheRestOfTheSecuringFlowForever() async {
        var checkCallCount = 0
        let (signal, fireWake) = makeSignal()
        let state = AppleSpeechAvailability(
            checkStatus: {
                checkCallCount += 1
                return .available
            },
            reserveAssets: {
                try? await Task.sleep(for: .seconds(3_600))
            },
            lifecycleSignal: signal,
            reserveDeadline: .milliseconds(50),
            checkStatusDeadline: .seconds(20)
        )

        await waitUntil { state.status == .available }
        XCTAssertEqual(checkCallCount, 1)

        fireWake()
        await waitUntil { checkCallCount >= 2 }
        XCTAssertEqual(checkCallCount, 2, "checkStatus must still run once the hung reserve call times out")
    }

    /// Same story for the status check itself: if it wedges, the module must not adopt
    /// a bogus status and must let the next trigger try again instead of getting stuck.
    func testHungCheckStatusCallLeavesLastKnownStatusAndAllowsARetry() async {
        var checkCallCount = 0
        let (signal, fireWake) = makeSignal()
        let state = AppleSpeechAvailability(
            checkStatus: {
                checkCallCount += 1
                if checkCallCount == 1 { return .available }
                try? await Task.sleep(for: .seconds(3_600))
                return .available
            },
            reserveAssets: {},
            lifecycleSignal: signal,
            checkStatusDeadline: .milliseconds(50)
        )

        await waitUntil { state.status == .available }
        XCTAssertEqual(checkCallCount, 1)

        fireWake()
        await waitUntil { checkCallCount >= 2 }
        try? await Task.sleep(for: .milliseconds(200))

        // The hung second check must not clobber the last known status.
        XCTAssertEqual(state.status, .available)

        fireWake()
        await waitUntil { checkCallCount >= 3 }
        XCTAssertEqual(checkCallCount, 3, "a later trigger must attempt checkStatus again, not stay wedged behind the hung one")
    }

    // MARK: - Persistent no-progress triggers a self-relaunch (poisoned XPC connection)

    /// Reproduces the observed field bug: a poisoned Apple Speech XPC connection fails
    /// every call fast (not a hang) with `.assetsNotInstalled`, forever, in this process —
    /// while a fresh process would succeed immediately. No amount of retrying from inside
    /// the same process ever recovers, so after enough no-progress rounds the module must
    /// give up and trigger a relaunch instead of leaving the user stuck indefinitely.
    func testPersistentNoProgressTriggersRelaunchAfterThreshold() async {
        var relaunchCount = 0
        let (signal, fireWake) = makeSignal()
        let state = AppleSpeechAvailability(
            checkStatus: { .assetsNotInstalled },
            requestAssetInstallation: { .assetsNotInstalled },
            reserveAssets: {},
            lifecycleSignal: signal,
            persistentFailureThreshold: 3,
            onPersistentFailure: { relaunchCount += 1 }
        )

        await waitUntil { !state.isInstallingAssets } // launch pass (round 1)
        fireWake() // round 2
        await waitUntil { !state.isInstallingAssets && relaunchCount == 0 }
        try? await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(relaunchCount, 0, "must not relaunch before the threshold is reached")

        fireWake() // round 3 — reaches the threshold
        await waitUntil { relaunchCount >= 1 }
        XCTAssertEqual(relaunchCount, 1)
    }

    /// A single successful round must reset the counter — brief blips shouldn't accumulate
    /// toward a relaunch across unrelated later failures.
    func testProgressResetsTheFailureCounter() async {
        var relaunchCount = 0
        var checkCallCount = 0
        let (signal, fireWake) = makeSignal()
        let state = AppleSpeechAvailability(
            checkStatus: {
                checkCallCount += 1
                // Rounds 1, 2 fail; round 3 succeeds; rounds 4, 5 fail again.
                return checkCallCount == 3 ? .available : .assetsNotInstalled
            },
            requestAssetInstallation: { .assetsNotInstalled },
            reserveAssets: {},
            lifecycleSignal: signal,
            persistentFailureThreshold: 3,
            onPersistentFailure: { relaunchCount += 1 }
        )

        await waitUntil { checkCallCount >= 1 } // round 1
        fireWake()
        await waitUntil { checkCallCount >= 2 } // round 2
        fireWake()
        await waitUntil { checkCallCount >= 3 } // round 3 — succeeds, resets counter
        fireWake()
        await waitUntil { checkCallCount >= 4 } // round 4
        fireWake()
        await waitUntil { checkCallCount >= 5 } // round 5 — only 2 failures since the reset
        try? await Task.sleep(for: .milliseconds(20))

        XCTAssertEqual(relaunchCount, 0, "the successful round must have reset the streak")
    }

    /// A permanently unsupported machine/OS must never relaunch — restarting cannot fix it,
    /// so counting toward the threshold there would just loop the app forever for nothing.
    func testUnsupportedStatusNeverTriggersRelaunch() async {
        var relaunchCount = 0
        let (signal, fireWake) = makeSignal()
        let state = AppleSpeechAvailability(
            checkStatus: { .germanAssetsUnsupported },
            reserveAssets: {},
            lifecycleSignal: signal,
            persistentFailureThreshold: 2,
            onPersistentFailure: { relaunchCount += 1 }
        )

        await waitUntil { state.status == .germanAssetsUnsupported }
        fireWake()
        fireWake()
        fireWake()
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(relaunchCount, 0)
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
