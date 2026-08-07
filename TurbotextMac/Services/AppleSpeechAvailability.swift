import AppKit
import Observation

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

    private let checkStatus: () async -> AppleSpeechAvailabilityStatus
    private let requestAssetInstallation: () async throws -> AppleSpeechAvailabilityStatus
    private let reserveAssets: () async -> Void
    private var installTask: Task<Result<AppleSpeechAvailabilityStatus, Error>, Never>?

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
        lifecycleSignal: AppLifecycleSignal = .system
    ) {
        self.checkStatus = checkStatus
        self.requestAssetInstallation = requestAssetInstallation
        self.reserveAssets = reserveAssets

        lifecycleSignal.subscribe { [weak self] in
            Task { @MainActor in await self?.ensureAssetsReady() }
        }
        Task { @MainActor [weak self] in await self?.ensureAssetsReady() }
    }

    /// Reserves the Sprachassets, rechecks their status, and installs them if they're
    /// missing but installable — then reserves again on success. Safe to call from
    /// multiple triggers at once: concurrent calls share a single running installation.
    func ensureAssetsReady() async {
        await reserveAssets()
        status = await checkStatus()
        guard status.isAssetInstallationPossible else { return }
        await performInstall()
    }

    private func performInstall() async {
        let isOwner = installTask == nil
        if isOwner {
            isInstallingAssets = true
            assetInstallationErrorText = nil
            let requestAssetInstallation = requestAssetInstallation
            installTask = Task {
                do {
                    return .success(try await requestAssetInstallation())
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
        case .failure(let error):
            assetInstallationErrorText = "Die Installation der Apple-Sprachassets ist fehlgeschlagen: \(error.localizedDescription)"
        }
    }
}
