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

    var isAvailable: Bool { status.isAvailable }

    init(
        checkStatus: @escaping () async -> AppleSpeechAvailabilityStatus = { await AppleSpeechAvailability.status },
        requestAssetInstallation: @escaping () async throws -> AppleSpeechAvailabilityStatus = { try await AppleSpeechAvailability.installAssets() }
    ) {
        self.checkStatus = checkStatus
        self.requestAssetInstallation = requestAssetInstallation
    }

    func refresh() {
        Task { @MainActor [weak self, checkStatus] in
            self?.status = await checkStatus()
        }
    }

    func installAssets() {
        guard status == .assetsNotInstalled, !isInstallingAssets else { return }

        isInstallingAssets = true
        assetInstallationErrorText = nil

        Task { @MainActor [weak self, requestAssetInstallation] in
            defer { self?.isInstallingAssets = false }

            do {
                self?.status = try await requestAssetInstallation()
            } catch {
                self?.assetInstallationErrorText = "Die Installation der Apple-Sprachassets ist fehlgeschlagen: \(error.localizedDescription)"
            }
        }
    }
}
