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
        let persistence = InMemoryPersistence()
        let favorites = makeFavoritesStore()
        favorites.addFavorite(uid: "usb-mic")
        let service = MicrophoneAutoSelectionService(
            favoritesStore: favorites,
            selectedMicUIDKey: key,
            deviceProvider: { [self.device("usb-mic")] },
            defaults: persistence
        )

        service.applySelection()

        XCTAssertEqual(persistence.string(forKey: key), "usb-mic")
    }

    func testClearsStaleSelectedUIDWhenFavoriteBecomesUnavailable() {
        let key = "test_selectedMicUID_\(UUID().uuidString)"
        let persistence = InMemoryPersistence()
        persistence.set("usb-mic", forKey: key)
        let favorites = makeFavoritesStore()
        favorites.addFavorite(uid: "usb-mic")
        let service = MicrophoneAutoSelectionService(
            favoritesStore: favorites,
            selectedMicUIDKey: key,
            deviceProvider: { [] },
            defaults: persistence
        )

        service.applySelection()

        XCTAssertNil(persistence.string(forKey: key))
    }

    func testSwitchesToAvailableFavoriteAfterDeviceChange() {
        let key = "test_selectedMicUID_\(UUID().uuidString)"
        let persistence = InMemoryPersistence()
        let favorites = makeFavoritesStore()
        favorites.addFavorite(uid: "headset-mic")
        var available: [AudioInputDevice] = []
        let service = MicrophoneAutoSelectionService(
            favoritesStore: favorites,
            selectedMicUIDKey: key,
            deviceProvider: { available },
            defaults: persistence
        )

        service.applySelection()
        XCTAssertNil(persistence.string(forKey: key), "no favorite available yet")

        available = [self.device("headset-mic")]
        service.applySelection()
        XCTAssertEqual(persistence.string(forKey: key), "headset-mic", "favorite plugged in → selected")
    }

    func testClearsStaleSelectedUIDWhenUseSystemDefaultEnabled() {
        let key = "test_selectedMicUID_\(UUID().uuidString)"
        let persistence = InMemoryPersistence()
        persistence.set("usb-mic", forKey: key)
        let favorites = makeFavoritesStore()
        favorites.addFavorite(uid: "usb-mic")
        favorites.useSystemDefault = true
        let service = MicrophoneAutoSelectionService(
            favoritesStore: favorites,
            selectedMicUIDKey: key,
            deviceProvider: { [self.device("usb-mic")] },
            defaults: persistence
        )

        service.applySelection()

        XCTAssertNil(persistence.string(forKey: key))
    }
}
