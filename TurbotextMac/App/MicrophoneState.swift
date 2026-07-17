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

    /// The currently resolved active microphone, kept in sync by
    /// `MicrophoneAutoSelectionService` on every hardware change.
    private(set) var activeMicrophone: ActiveMicrophone

    var favorites: [String] { favoritesStore.favoriteUIDs }
    var useSystemDefault: Bool {
        get { favoritesStore.useSystemDefault }
        set {
            favoritesStore.useSystemDefault = newValue
            autoSelectionService.applySelection()
        }
    }

    var activeDeviceDisplayName: String {
        guard let uid = activeMicrophone.uid,
              let match = deviceProvider().first(where: { $0.uid == uid }) else {
            return "Mikrofon"
        }
        return match.name
    }

    init(
        favoritesStore: MicrophoneFavoritesStore = MicrophoneFavoritesStore(),
        deviceProvider: @escaping () -> [AudioInputDevice] = MicrophoneService.availableInputDevices,
        defaultDeviceIDProvider: @escaping () -> AudioDeviceID? = MicrophoneService.defaultInputDeviceID,
        persistence: PersistenceProvider = UserDefaultsPersistence.shared
    ) {
        self.favoritesStore = favoritesStore
        self.deviceProvider = deviceProvider
        self.activeMicrophone = ActiveMicrophone(uid: nil, source: .systemDefault)
        self.autoSelectionService = MicrophoneAutoSelectionService(
            favoritesStore: favoritesStore,
            deviceProvider: deviceProvider,
            defaultDeviceIDProvider: defaultDeviceIDProvider,
            defaults: persistence
        )
        autoSelectionService.onSelectionApplied = { [weak self] resolved in
            self?.activeMicrophone = resolved
        }
    }

    func start() {
        autoSelectionService.start()
    }

    func addFavorite(uid: String) {
        favoritesStore.addFavorite(uid: uid)
        autoSelectionService.applySelection()
    }

    func removeFavorite(uid: String) {
        favoritesStore.removeFavorite(uid: uid)
        autoSelectionService.applySelection()
    }

    func moveUp(uid: String) {
        favoritesStore.moveUp(uid: uid)
        autoSelectionService.applySelection()
    }

    func moveDown(uid: String) {
        favoritesStore.moveDown(uid: uid)
        autoSelectionService.applySelection()
    }
}
