import CoreAudio
import Foundation
import Observation

/// The microphone Turbotext actually uses for app-internal recording, and why.
/// `.favorite` means a favorited device was found among the available devices;
/// `.systemDefault` means no favorite matched (or favorites are disabled), so the
/// macOS default input device is used — app-internally only (see ADR-0003).
struct ActiveMicrophone: Equatable {
    enum Source: Equatable {
        case favorite
        case systemDefault
    }

    let uid: String?
    let source: Source
}

@Observable
final class MicrophoneFavoritesStore {
    private let favoritesKey: String
    private let useSystemDefaultKey: String
    private let defaults: PersistenceProvider

    private(set) var favoriteUIDs: [String]
    var useSystemDefault: Bool {
        didSet {
            guard oldValue != useSystemDefault else { return }
            defaults.set(useSystemDefault, forKey: useSystemDefaultKey)
        }
    }

    init(
        favoritesKey: String = "turbotext.microphoneFavorites",
        useSystemDefaultKey: String = "turbotext.microphoneUseSystemDefault",
        defaults: PersistenceProvider = UserDefaultsPersistence.shared
    ) {
        self.favoritesKey = favoritesKey
        self.useSystemDefaultKey = useSystemDefaultKey
        self.defaults = defaults
        self.favoriteUIDs = Self.load(key: favoritesKey, defaults: defaults) ?? []
        self.useSystemDefault = defaults.bool(forKey: useSystemDefaultKey)
    }

    func addFavorite(uid: String) {
        guard !favoriteUIDs.contains(uid) else { return }
        favoriteUIDs = favoriteUIDs + [uid]
        persist()
    }

    func removeFavorite(uid: String) {
        favoriteUIDs = favoriteUIDs.filter { $0 != uid }
        persist()
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        var updated = favoriteUIDs
        updated.move(fromOffsets: source, toOffset: destination)
        favoriteUIDs = updated
        persist()
    }

    func moveUp(uid: String) {
        guard let index = favoriteUIDs.firstIndex(of: uid), index > 0 else { return }
        var updated = favoriteUIDs
        updated.swapAt(index, index - 1)
        favoriteUIDs = updated
        persist()
    }

    func moveDown(uid: String) {
        guard let index = favoriteUIDs.firstIndex(of: uid), index < favoriteUIDs.count - 1 else { return }
        var updated = favoriteUIDs
        updated.swapAt(index, index + 1)
        favoriteUIDs = updated
        persist()
    }

    /// Pure decision logic for "which microphone is active?": takes the current
    /// availability/default snapshot and returns the resolved microphone. Callers are
    /// responsible for applying the result (e.g. persisting `uid` for `AudioRecorder`
    /// to read). Never touches the macOS-wide default input device (see ADR-0003).
    func resolveActiveDevice(
        availableDevices: [AudioInputDevice],
        systemDefaultID: AudioDeviceID?
    ) -> ActiveMicrophone {
        if !useSystemDefault,
           let favorite = favoriteUIDs.lazy.compactMap({ uid in availableDevices.first { $0.uid == uid } }).first {
            return ActiveMicrophone(uid: favorite.uid, source: .favorite)
        }
        let defaultUID = systemDefaultID.flatMap { id in availableDevices.first { $0.id == id }?.uid }
        return ActiveMicrophone(uid: defaultUID, source: .systemDefault)
    }

    private func persist() {
        defaults.set(favoriteUIDs, forKey: favoritesKey)
    }

    private static func load(key: String, defaults: PersistenceProvider) -> [String]? {
        defaults.stringArray(forKey: key)
    }
}
