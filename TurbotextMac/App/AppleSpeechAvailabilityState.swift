import Observation

/// Caches Apple Speech's async availability check as a synchronous, observable flag so
/// the (synchronous) workflow factory can read it without blocking. Starts `false` and
/// flips true once the background check resolves — same pattern as `LocalModelState`.
@Observable
@MainActor
final class AppleSpeechAvailabilityState {
    private(set) var status: AppleSpeechAvailabilityStatus = .assetsNotInstalled
    private let checkStatus: () async -> AppleSpeechAvailabilityStatus

    var isAvailable: Bool { status.isAvailable }

    init(checkStatus: @escaping () async -> AppleSpeechAvailabilityStatus = { await AppleSpeechAvailability.status }) {
        self.checkStatus = checkStatus
    }

    func refresh() {
        Task { @MainActor [weak self, checkStatus] in
            self?.status = await checkStatus()
        }
    }
}
