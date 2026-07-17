import Observation

/// Caches Apple Speech's async availability check as a synchronous, observable flag so
/// the (synchronous) workflow factory can read it without blocking. Starts `false` and
/// flips true once the background check resolves — same pattern as `LocalModelState`.
@Observable
@MainActor
final class AppleSpeechAvailabilityState {
    private(set) var isAvailable = false
    private let checkAvailability: () async -> Bool

    init(checkAvailability: @escaping () async -> Bool = { await AppleSpeechAvailability.isAvailable }) {
        self.checkAvailability = checkAvailability
    }

    func refresh() {
        Task { @MainActor [weak self, checkAvailability] in
            let available = await checkAvailability()
            self?.isAvailable = available
        }
    }
}
