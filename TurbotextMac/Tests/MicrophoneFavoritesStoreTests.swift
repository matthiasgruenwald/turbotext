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

    // MARK: - resolveActiveDevice

    private func device(_ uid: String, name: String? = nil) -> AudioInputDevice {
        AudioInputDevice(id: AudioDeviceID(abs(uid.hashValue) % Int(UInt32.max)), name: name ?? uid, uid: uid)
    }

    func testResolvesHighestPriorityAvailableFavorite() {
        let store = makeStore()
        store.addFavorite(uid: "docking-station-A")
        store.addFavorite(uid: "docking-station-B")
        store.addFavorite(uid: "built-in")
        let available = [device("built-in"), device("docking-station-B")]

        let result = store.resolveActiveDevice(availableDevices: available, systemDefaultID: nil)

        XCTAssertEqual(result, ActiveMicrophone(uid: "docking-station-B", source: .favorite))
    }

    func testFallsBackToSystemDefaultWhenNoFavoriteAvailable() {
        let store = makeStore()
        store.addFavorite(uid: "docking-station-A")
        let defaultDevice = device("built-in")

        let result = store.resolveActiveDevice(availableDevices: [defaultDevice], systemDefaultID: defaultDevice.id)

        XCTAssertEqual(result, ActiveMicrophone(uid: "built-in", source: .systemDefault))
    }

    func testFallsBackToSystemDefaultWhenUseSystemDefaultEnabledEvenIfFavoriteAvailable() {
        let store = makeStore()
        store.addFavorite(uid: "built-in")
        store.useSystemDefault = true
        let favoriteDevice = device("built-in")

        let result = store.resolveActiveDevice(availableDevices: [favoriteDevice], systemDefaultID: favoriteDevice.id)

        XCTAssertEqual(result, ActiveMicrophone(uid: "built-in", source: .systemDefault))
    }

    func testResolvesNilUIDWhenNothingAvailable() {
        let store = makeStore()
        store.addFavorite(uid: "docking-station-A")

        let result = store.resolveActiveDevice(availableDevices: [], systemDefaultID: nil)

        XCTAssertEqual(result, ActiveMicrophone(uid: nil, source: .systemDefault))
    }

    func testResolvesNilUIDWhenFavoritesEmptyAndNoSystemDefaultMatch() {
        let store = makeStore()

        let result = store.resolveActiveDevice(availableDevices: [device("built-in")], systemDefaultID: nil)

        XCTAssertEqual(result, ActiveMicrophone(uid: nil, source: .systemDefault))
    }
}
