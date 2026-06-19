import Foundation
import Observation

@Observable
final class MicrophoneFavoritesStore {
    private let favoritesKey: String
    private let useSystemDefaultKey: String

    private(set) var favoriteUIDs: [String]
    var useSystemDefault: Bool {
        didSet {
            guard oldValue != useSystemDefault else { return }
            UserDefaults.standard.set(useSystemDefault, forKey: useSystemDefaultKey)
        }
    }

    init(
        favoritesKey: String = "turbotext.microphoneFavorites",
        useSystemDefaultKey: String = "turbotext.microphoneUseSystemDefault"
    ) {
        self.favoritesKey = favoritesKey
        self.useSystemDefaultKey = useSystemDefaultKey
        self.favoriteUIDs = Self.load(key: favoritesKey) ?? []
        self.useSystemDefault = UserDefaults.standard.bool(forKey: useSystemDefaultKey)
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

    /// Pure selection logic: given the prioritized favorites list and the currently
    /// available devices, returns the highest-priority device that is actually available.
    /// Returns nil if no favorite is available (caller should fall back to the system default).
    func selectedDevice(from availableDevices: [AudioInputDevice]) -> AudioInputDevice? {
        guard !useSystemDefault else { return nil }
        for uid in favoriteUIDs {
            if let match = availableDevices.first(where: { $0.uid == uid }) {
                return match
            }
        }
        return nil
    }

    private func persist() {
        UserDefaults.standard.set(favoriteUIDs, forKey: favoritesKey)
    }

    private static func load(key: String) -> [String]? {
        UserDefaults.standard.stringArray(forKey: key)
    }
}
