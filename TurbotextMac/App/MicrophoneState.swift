import CoreAudio
import Observation

/// Owns microphone favorites and auto-selection. Wraps `MicrophoneFavoritesStore` and
/// `MicrophoneAutoSelectionService` (both already seamed via `PersistenceProvider`, #69).
/// `AppState` delegates here; this type does not know about `AppState` directly.
@Observable
@MainActor
final class MicrophoneState {
    let favoritesStore: MicrophoneFavoritesStore
    private let autoSelectionService: MicrophoneAutoSelectionService
    private let deviceProvider: () -> [AudioInputDevice]
    private let defaultDeviceIDProvider: () -> AudioDeviceID?

    /// Bumped whenever `MicrophoneAutoSelectionService` re-evaluates the active device,
    /// so views reading `activeDeviceDisplayName` get invalidated on hardware changes.
    private(set) var deviceSignal = 0

    var favorites: [String] { favoritesStore.favoriteUIDs }
    var useSystemDefault: Bool {
        get { favoritesStore.useSystemDefault }
        set { favoritesStore.useSystemDefault = newValue }
    }

    var activeDeviceDisplayName: String {
        _ = deviceSignal
        return favoritesStore.activeDeviceDisplayName(
            availableDevices: deviceProvider(),
            defaultDeviceID: defaultDeviceIDProvider()
        )
    }

    init(
        favoritesStore: MicrophoneFavoritesStore = MicrophoneFavoritesStore(),
        deviceProvider: @escaping () -> [AudioInputDevice] = MicrophoneService.availableInputDevices,
        defaultDeviceIDProvider: @escaping () -> AudioDeviceID? = MicrophoneService.defaultInputDeviceID,
        persistence: PersistenceProvider = UserDefaultsPersistence.shared
    ) {
        self.favoritesStore = favoritesStore
        self.deviceProvider = deviceProvider
        self.defaultDeviceIDProvider = defaultDeviceIDProvider
        self.autoSelectionService = MicrophoneAutoSelectionService(
            favoritesStore: favoritesStore,
            deviceProvider: deviceProvider,
            defaults: persistence
        )
        autoSelectionService.onSelectionApplied = { [weak self] in
            self?.deviceSignal += 1
        }
    }

    func start() {
        autoSelectionService.start()
    }

    func addFavorite(uid: String) {
        favoritesStore.addFavorite(uid: uid)
    }

    func removeFavorite(uid: String) {
        favoritesStore.removeFavorite(uid: uid)
    }

    func moveUp(uid: String) {
        favoritesStore.moveUp(uid: uid)
    }

    func moveDown(uid: String) {
        favoritesStore.moveDown(uid: uid)
    }
}
