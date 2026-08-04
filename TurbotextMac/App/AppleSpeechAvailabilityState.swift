import Observation

/// Caches Apple Speech's async availability check as a synchronous, observable flag so
/// the (synchronous) workflow factory can read it without blocking. Starts `false` and
/// flips true once the background check resolves — same pattern as `LocalModelState`.
@Observable
@MainActor
final class AppleSpeechAvailabilityState {
    private(set) var status: AppleSpeechAvailabilityStatus = .assetsNotInstalled
    private(set) var isInstallingAssets = false
    private(set) var assetInstallationErrorText: String?
    private let checkStatus: () async -> AppleSpeechAvailabilityStatus
    private let requestAssetInstallation: () async throws -> AppleSpeechAvailabilityStatus
    private let reserveAssets: () async -> Void

    var isAvailable: Bool { status.isAvailable }

    init(
        checkStatus: @escaping () async -> AppleSpeechAvailabilityStatus = { await AppleSpeechAvailability.status },
        requestAssetInstallation: @escaping () async throws -> AppleSpeechAvailabilityStatus = { try await AppleSpeechAvailability.installAssets() },
        reserveAssets: @escaping () async -> Void = { await AppleSpeechAvailability.reserveAssets() }
    ) {
        self.checkStatus = checkStatus
        self.requestAssetInstallation = requestAssetInstallation
        self.reserveAssets = reserveAssets
    }

    func refresh() {
        Task { @MainActor [weak self, checkStatus] in
            self?.status = await checkStatus()
        }
    }

    /// Sprachasset-Sicherstellung (#178): Beim Start reservieren, damit macOS die
    /// Assets nicht deaktiviert oder entfernt; fehlen sie danach dennoch, die
    /// Installation selbst anstoßen.
    func secureAssetsAtLaunch() {
        Task { @MainActor [weak self, reserveAssets] in
            await reserveAssets()
            await self?.refreshStatusAndInstallIfNeeded()
        }
    }

    /// Sicherstellung auf Tastendruck (#178): Der Frühcheck der Live-Session hat den
    /// Status gerade frisch als nicht bereit gemeldet — der zwischengespeicherte Status
    /// kann noch `.available` sagen, deshalb hier erneut prüfen statt blind installieren.
    func secureAssetsOnDemand() {
        Task { @MainActor [weak self] in
            await self?.refreshStatusAndInstallIfNeeded()
        }
    }

    func installAssets() {
        guard status == .assetsNotInstalled, !isInstallingAssets else { return }

        isInstallingAssets = true
        assetInstallationErrorText = nil

        Task { @MainActor [weak self, requestAssetInstallation, reserveAssets] in
            defer { self?.isInstallingAssets = false }

            do {
                let newStatus = try await requestAssetInstallation()
                guard let self else { return }
                self.status = newStatus
                if newStatus.isAvailable {
                    await reserveAssets()
                }
            } catch {
                self?.assetInstallationErrorText = "Die Installation der Apple-Sprachassets ist fehlgeschlagen: \(error.localizedDescription)"
            }
        }
    }

    private func refreshStatusAndInstallIfNeeded() async {
        status = await checkStatus()
        installAssets()
    }
}
