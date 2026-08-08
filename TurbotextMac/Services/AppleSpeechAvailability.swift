import AppKit
import Observation
import OSLog

private let securingLogger = Logger(subsystem: "app.turbotext.mac", category: "LiveDictation")

/// Whether Apple-Gerätetranskription is usable right now, for callers that need to
/// decide synchronously (start gates, backend resolution) rather than observe.
enum AppleSpeechReadiness: Equatable {
    case ready
    case notReady(reason: AppleSpeechAvailabilityStatus, canInstall: Bool)

    var isReady: Bool { self == .ready }
}

/// Notifies about moments that can invalidate the Sprachasset reservation — waking
/// from standby and the app becoming active — so `AppleSpeechAvailability` can
/// re-secure it without any caller asking (#189, fixes F3 from #188). Injectable so
/// tests can fire the signal without touching real system sleep or app activation.
struct AppLifecycleSignal: Sendable {
    var subscribe: @Sendable (@escaping @Sendable () -> Void) -> Void

    @MainActor
    static let system = AppLifecycleSignal { handler in
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { _ in handler() }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { _ in handler() }
    }
}

/// Owns Sprachasset-Bereitschaft (#189, siehe CONTEXT.md): reserves the assets against
/// macOS, checks their status, and installs them when missing but installable — run at
/// app start and re-run, unprompted, whenever the app wakes from standby or becomes
/// active, since either can have let macOS deactivate or remove the reservation.
///
/// Interface is deliberately narrow: `status`/`isInstallingAssets`/`assetInstallationErrorText`
/// for views to observe, `readiness` for synchronous start decisions, and `ensureAssetsReady()`
/// for anyone who needs the securing flow to run right now (e.g. the live session's early
/// check). The reserve/check/install/re-reserve steps themselves are an internal flow, not
/// separately callable — that used to be four public verbs and made "did we recheck after
/// wake" a per-caller question instead of this module's own job.
///
/// Absorbs the previous version-erasing façade over `AppleSpeechTranscriptionService`
/// (macOS 26+ only): the `#available` guards live directly in the default closures below
/// instead of as their own module.
@Observable
@MainActor
final class AppleSpeechAvailability {
    private(set) var status: AppleSpeechAvailabilityStatus = .assetsNotInstalled
    private(set) var isInstallingAssets = false
    private(set) var assetInstallationErrorText: String?

    /// Bounds every macOS Speech-framework call this module makes. Standby can wedge any
    /// of `reserve`, `status`, or `downloadAndInstall()` indefinitely — not only the install
    /// call — since all three go through the same XPC-backed asset daemon; an un-deadlined
    /// await there survives forever and blocks every later retry behind it. Reserve/status
    /// are normally near-instant, so they get a short bound; install gets a long one since a
    /// genuinely slow download must not be mistaken for a hang.
    private static let reserveDeadline: Duration = .seconds(20)
    private static let checkStatusDeadline: Duration = .seconds(20)
    private static let installDeadline: Duration = .seconds(180)

    /// A poisoned Apple Speech XPC connection (observed after standby) fails every call
    /// fast and permanently, indistinguishable from here except by "still not ready after
    /// several full securing attempts". Restarting the process is the only known recovery
    /// (fresh XPC bootstrap) — matches what manually quitting and reopening the app already
    /// does. This many consecutive no-progress rounds before doing that automatically.
    private static let persistentFailureThreshold = 3

    private let checkStatus: () async -> AppleSpeechAvailabilityStatus
    private let requestAssetInstallation: () async throws -> AppleSpeechAvailabilityStatus
    private let reserveAssets: () async -> Void
    private let reserveDeadline: Duration
    private let checkStatusDeadline: Duration
    private let installDeadline: Duration
    private let persistentFailureThreshold: Int
    private let onPersistentFailure: @MainActor () -> Void
    private var installTask: Task<Result<AppleSpeechAvailabilityStatus, Error>, Never>?
    private var consecutiveUnsuccessfulSecurings = 0

    var readiness: AppleSpeechReadiness {
        status.isAvailable ? .ready : .notReady(reason: status, canInstall: status.isAssetInstallationPossible)
    }

    init(
        checkStatus: @escaping () async -> AppleSpeechAvailabilityStatus = {
            guard #available(macOS 26, *) else { return .unsupportedOS }
            return await AppleSpeechTranscriptionService.availabilityStatus
        },
        requestAssetInstallation: @escaping () async throws -> AppleSpeechAvailabilityStatus = {
            guard #available(macOS 26, *) else { throw AppleSpeechAssetInstallationError.unsupportedOS }
            return try await AppleSpeechTranscriptionService.installAssets()
        },
        reserveAssets: @escaping () async -> Void = {
            guard #available(macOS 26, *) else { return }
            await AppleSpeechTranscriptionService.reserveAssets()
        },
        lifecycleSignal: AppLifecycleSignal = .system,
        reserveDeadline: Duration = AppleSpeechAvailability.reserveDeadline,
        checkStatusDeadline: Duration = AppleSpeechAvailability.checkStatusDeadline,
        installDeadline: Duration = AppleSpeechAvailability.installDeadline,
        persistentFailureThreshold: Int = AppleSpeechAvailability.persistentFailureThreshold,
        onPersistentFailure: @escaping @MainActor () -> Void = AppSelfRelauncher.relaunch
    ) {
        self.checkStatus = checkStatus
        self.requestAssetInstallation = requestAssetInstallation
        self.reserveAssets = reserveAssets
        self.reserveDeadline = reserveDeadline
        self.checkStatusDeadline = checkStatusDeadline
        self.installDeadline = installDeadline
        self.persistentFailureThreshold = persistentFailureThreshold
        self.onPersistentFailure = onPersistentFailure

        lifecycleSignal.subscribe { [weak self] in
            Task { @MainActor in await self?.ensureAssetsReady() }
        }
        Task { @MainActor [weak self] in await self?.ensureAssetsReady() }
    }

    /// Reserves the Sprachassets, rechecks their status, and installs them if they're
    /// missing but installable — then reserves again on success. Safe to call from
    /// multiple triggers at once: concurrent calls share a single running installation.
    func ensureAssetsReady() async {
        let reserveAssets = reserveAssets
        _ = try? await TranscriptionDeadline.run(within: reserveDeadline) {
            await reserveAssets()
        }

        let checkStatus = checkStatus
        guard let newStatus = try? await TranscriptionDeadline.run(within: checkStatusDeadline, operation: {
            await checkStatus()
        }) else {
            // Status check itself wedged — keep the last known status and let the
            // next trigger (wake, retry) try again rather than guessing here.
            recordSecuringOutcome(status: nil)
            return
        }
        status = newStatus
        guard status.isAssetInstallationPossible else {
            recordSecuringOutcome(status: status)
            return
        }
        await performInstall()
        recordSecuringOutcome(status: status)
    }

    /// Tracks whether securing is making any progress at all. `nil` means the status check
    /// itself timed out — as much a failed round as a checked-but-still-not-ready status.
    /// Unsupported statuses never count: no retry, install, or restart fixes those, so they
    /// reset the counter instead of feeding a restart that couldn't possibly help.
    private func recordSecuringOutcome(status: AppleSpeechAvailabilityStatus?) {
        switch status {
        case .available, .unsupportedOS, .germanAssetsUnsupported:
            consecutiveUnsuccessfulSecurings = 0
        case .assetsNotInstalled, .assetsDownloading, nil:
            consecutiveUnsuccessfulSecurings += 1
            guard consecutiveUnsuccessfulSecurings >= persistentFailureThreshold else { return }
            consecutiveUnsuccessfulSecurings = 0
            securingLogger.error(
                "apple speech securing made no progress across \(self.persistentFailureThreshold) rounds — relaunching"
            )
            onPersistentFailure()
        }
    }

    private func performInstall() async {
        let isOwner = installTask == nil
        if isOwner {
            isInstallingAssets = true
            assetInstallationErrorText = nil
            let requestAssetInstallation = requestAssetInstallation
            let installDeadline = installDeadline
            installTask = Task {
                do {
                    return .success(try await TranscriptionDeadline.run(within: installDeadline) {
                        try await requestAssetInstallation()
                    })
                } catch {
                    return .failure(error)
                }
            }
        }
        guard let task = installTask else { return }
        let result = await task.value
        guard isOwner else { return }

        installTask = nil
        isInstallingAssets = false
        switch result {
        case .success(let newStatus):
            status = newStatus
            if newStatus.isAvailable {
                await reserveAssets()
            }
        case .failure(is TranscriptionDeadline.Exceeded):
            assetInstallationErrorText = "Die Installation der Apple-Sprachassets dauert ungewöhnlich lange und wurde abgebrochen — bitte erneut versuchen."
        case .failure(let error):
            assetInstallationErrorText = "Die Installation der Apple-Sprachassets ist fehlgeschlagen: \(error.localizedDescription)"
        }
    }
}
