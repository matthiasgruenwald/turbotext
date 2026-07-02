import XCTest
import CoreAudio
@testable import Turbotext

@MainActor
final class MicrophoneStateTests: XCTestCase {

    private let favoritesKey = "test_favorites_key"

    private func makeState(persistence: PersistenceProvider = InMemoryPersistence()) -> MicrophoneState {
        MicrophoneState(
            favoritesStore: MicrophoneFavoritesStore(
                favoritesKey: favoritesKey,
                useSystemDefaultKey: "test_useSystemDefault_\(UUID().uuidString)",
                defaults: persistence
            ),
            deviceProvider: { [] },
            persistence: persistence
        )
    }

    func testFavoritesStartsEmpty() {
        let state = makeState()
        XCTAssertTrue(state.favorites.isEmpty)
    }

    func testAddFavoriteUpdatesFavorites() {
        let state = makeState()
        state.addFavorite(uid: "usb-mic")
        XCTAssertEqual(state.favorites, ["usb-mic"])
    }

    func testMoveUpReordersFavorites() {
        let state = makeState()
        state.addFavorite(uid: "a")
        state.addFavorite(uid: "b")

        state.moveUp(uid: "b")

        XCTAssertEqual(state.favorites, ["b", "a"])
    }

    func testMoveDownReordersFavorites() {
        let state = makeState()
        state.addFavorite(uid: "a")
        state.addFavorite(uid: "b")

        state.moveDown(uid: "a")

        XCTAssertEqual(state.favorites, ["b", "a"])
    }

    func testActiveDeviceDisplayNameFallsBackToPlaceholderWhenNoDeviceAvailable() {
        let state = makeState()
        XCTAssertEqual(state.activeDeviceDisplayName, "Mikrofon")
    }

    func testUsesPersistenceProviderNotUserDefaultsDirectly() {
        let persistence = InMemoryPersistence()
        let state = makeState(persistence: persistence)

        state.addFavorite(uid: "usb-mic")

        XCTAssertEqual(persistence.stringArray(forKey: favoritesKey), ["usb-mic"])
    }
}
