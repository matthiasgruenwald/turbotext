import XCTest
import CoreAudio
@testable import Turbotext

// MARK: - MicrophoneFavoritesStore mutation

final class MicrophoneFavoritesStoreTests: XCTestCase {

    private func makeStore() -> MicrophoneFavoritesStore {
        MicrophoneFavoritesStore(
            favoritesKey: "test_favorites_\(UUID().uuidString)",
            useSystemDefaultKey: "test_useSystemDefault_\(UUID().uuidString)"
        )
    }

    func testStartsEmpty() {
        let store = makeStore()
        XCTAssertTrue(store.favoriteUIDs.isEmpty)
        XCTAssertFalse(store.useSystemDefault)
    }

    func testAddFavoriteAppends() {
        let store = makeStore()
        store.addFavorite(uid: "mic-1")
        store.addFavorite(uid: "mic-2")
        XCTAssertEqual(store.favoriteUIDs, ["mic-1", "mic-2"])
    }

    func testAddFavoriteIgnoresDuplicate() {
        let store = makeStore()
        store.addFavorite(uid: "mic-1")
        store.addFavorite(uid: "mic-1")
        XCTAssertEqual(store.favoriteUIDs, ["mic-1"])
    }

    func testRemoveFavoriteDropsUID() {
        let store = makeStore()
        store.addFavorite(uid: "mic-1")
        store.addFavorite(uid: "mic-2")
        store.removeFavorite(uid: "mic-1")
        XCTAssertEqual(store.favoriteUIDs, ["mic-2"])
    }

    func testMoveUpSwapsWithPrevious() {
        let store = makeStore()
        store.addFavorite(uid: "mic-1")
        store.addFavorite(uid: "mic-2")
        store.moveUp(uid: "mic-2")
        XCTAssertEqual(store.favoriteUIDs, ["mic-2", "mic-1"])
    }

    func testMoveUpAtTopIsNoop() {
        let store = makeStore()
        store.addFavorite(uid: "mic-1")
        store.addFavorite(uid: "mic-2")
        store.moveUp(uid: "mic-1")
        XCTAssertEqual(store.favoriteUIDs, ["mic-1", "mic-2"])
    }

    func testMoveDownSwapsWithNext() {
        let store = makeStore()
        store.addFavorite(uid: "mic-1")
        store.addFavorite(uid: "mic-2")
        store.moveDown(uid: "mic-1")
        XCTAssertEqual(store.favoriteUIDs, ["mic-2", "mic-1"])
    }

    func testMoveDownAtBottomIsNoop() {
        let store = makeStore()
        store.addFavorite(uid: "mic-1")
        store.addFavorite(uid: "mic-2")
        store.moveDown(uid: "mic-2")
        XCTAssertEqual(store.favoriteUIDs, ["mic-1", "mic-2"])
    }

    func testPersistsAcrossInstancesWithSameKey() {
        let key = "test_favorites_\(UUID().uuidString)"
        let defaultsKey = "test_useSystemDefault_\(UUID().uuidString)"
        let store1 = MicrophoneFavoritesStore(favoritesKey: key, useSystemDefaultKey: defaultsKey)
        store1.addFavorite(uid: "mic-1")

        let store2 = MicrophoneFavoritesStore(favoritesKey: key, useSystemDefaultKey: defaultsKey)
        XCTAssertEqual(store2.favoriteUIDs, ["mic-1"])
    }
}
