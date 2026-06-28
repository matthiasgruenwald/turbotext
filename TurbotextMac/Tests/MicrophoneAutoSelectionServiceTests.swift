import XCTest
import CoreAudio
@testable import Turbotext

@MainActor
final class MicrophoneAutoSelectionServiceTests: XCTestCase {

    private func device(_ uid: String) -> AudioInputDevice {
        AudioInputDevice(id: AudioDeviceID(abs(uid.hashValue) % Int(UInt32.max)), name: uid, uid: uid)
    }

    private func makeFavoritesStore() -> MicrophoneFavoritesStore {
        MicrophoneFavoritesStore(
            favoritesKey: "test_favorites_\(UUID().uuidString)",
            useSystemDefaultKey: "test_useSystemDefault_\(UUID().uuidString)"
        )
    }

    func testSetsSelectedUIDWhenFavoriteAvailable() {
        let key = "test_selectedMicUID_\(UUID().uuidString)"
        let favorites = makeFavoritesStore()
        favorites.addFavorite(uid: "usb-mic")
        let service = MicrophoneAutoSelectionService(
            favoritesStore: favorites,
            selectedMicUIDKey: key,
            deviceProvider: { [self.device("usb-mic")] }
        )

        service.applySelection()

        XCTAssertEqual(UserDefaults.standard.string(forKey: key), "usb-mic")
    }

    func testClearsStaleSelectedUIDWhenFavoriteBecomesUnavailable() {
        let key = "test_selectedMicUID_\(UUID().uuidString)"
        UserDefaults.standard.set("usb-mic", forKey: key)
        let favorites = makeFavoritesStore()
        favorites.addFavorite(uid: "usb-mic")
        let service = MicrophoneAutoSelectionService(
            favoritesStore: favorites,
            selectedMicUIDKey: key,
            deviceProvider: { [] }
        )

        service.applySelection()

        XCTAssertNil(UserDefaults.standard.string(forKey: key))
    }

    func testClearsStaleSelectedUIDWhenUseSystemDefaultEnabled() {
        let key = "test_selectedMicUID_\(UUID().uuidString)"
        UserDefaults.standard.set("usb-mic", forKey: key)
        let favorites = makeFavoritesStore()
        favorites.addFavorite(uid: "usb-mic")
        favorites.useSystemDefault = true
        let service = MicrophoneAutoSelectionService(
            favoritesStore: favorites,
            selectedMicUIDKey: key,
            deviceProvider: { [self.device("usb-mic")] }
        )

        service.applySelection()

        XCTAssertNil(UserDefaults.standard.string(forKey: key))
    }
}
