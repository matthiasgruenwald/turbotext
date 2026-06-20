import XCTest
import CoreAudio
@testable import Turbotext

final class MicrophoneFavoritesSelectionTests: XCTestCase {

    private func makeStore() -> MicrophoneFavoritesStore {
        MicrophoneFavoritesStore(
            favoritesKey: "test_favorites_\(UUID().uuidString)",
            useSystemDefaultKey: "test_useSystemDefault_\(UUID().uuidString)"
        )
    }

    private func device(_ uid: String, name: String? = nil) -> AudioInputDevice {
        AudioInputDevice(id: AudioDeviceID(abs(uid.hashValue) % Int(UInt32.max)), name: name ?? uid, uid: uid)
    }

    func testSelectsHighestPriorityAvailableDevice() {
        let store = makeStore()
        store.addFavorite(uid: "docking-station-A")
        store.addFavorite(uid: "docking-station-B")
        store.addFavorite(uid: "built-in")

        let available = [device("built-in"), device("docking-station-B")]
        let selected = store.selectedDevice(from: available)

        XCTAssertEqual(selected?.uid, "docking-station-B")
    }

    func testFallsBackToLowerPriorityWhenTopFavoriteUnavailable() {
        let store = makeStore()
        store.addFavorite(uid: "docking-station-A")
        store.addFavorite(uid: "built-in")

        let available = [device("built-in")]
        let selected = store.selectedDevice(from: available)

        XCTAssertEqual(selected?.uid, "built-in")
    }

    func testReturnsNilWhenNoFavoriteIsAvailable() {
        let store = makeStore()
        store.addFavorite(uid: "docking-station-A")

        let available = [device("built-in")]
        let selected = store.selectedDevice(from: available)

        XCTAssertNil(selected)
    }

    func testReturnsNilWhenFavoritesListIsEmpty() {
        let store = makeStore()
        let available = [device("built-in")]
        XCTAssertNil(store.selectedDevice(from: available))
    }

    func testReturnsNilWhenUseSystemDefaultIsEnabledEvenIfFavoriteAvailable() {
        let store = makeStore()
        store.addFavorite(uid: "built-in")
        store.useSystemDefault = true

        let available = [device("built-in")]
        XCTAssertNil(store.selectedDevice(from: available))
    }

    func testEmptyAvailableDevicesYieldsNil() {
        let store = makeStore()
        store.addFavorite(uid: "built-in")
        XCTAssertNil(store.selectedDevice(from: []))
    }
}

// MARK: - MicrophoneFavoritesStore active device display name

final class MicrophoneFavoritesActiveDisplayNameTests: XCTestCase {

    private func makeStore() -> MicrophoneFavoritesStore {
        MicrophoneFavoritesStore(
            favoritesKey: "test_favorites_\(UUID().uuidString)",
            useSystemDefaultKey: "test_useSystemDefault_\(UUID().uuidString)"
        )
    }

    private func device(_ uid: String, name: String? = nil) -> AudioInputDevice {
        AudioInputDevice(id: AudioDeviceID(abs(uid.hashValue) % Int(UInt32.max)), name: name ?? uid, uid: uid)
    }

    func testUsesTopFavoriteNameWhenNotUsingSystemDefault() {
        let store = makeStore()
        store.addFavorite(uid: "built-in")
        let available = [device("built-in", name: "MacBook Mikrofon")]

        let name = store.activeDeviceDisplayName(availableDevices: available, defaultDeviceID: nil)

        XCTAssertEqual(name, "MacBook Mikrofon")
    }

    func testFallsBackToDefaultDeviceNameWhenUsingSystemDefault() {
        let store = makeStore()
        store.useSystemDefault = true
        let defaultDevice = device("built-in", name: "MacBook Mikrofon")

        let name = store.activeDeviceDisplayName(availableDevices: [defaultDevice], defaultDeviceID: defaultDevice.id)

        XCTAssertEqual(name, "MacBook Mikrofon")
    }

    func testFallsBackToDefaultDeviceNameWhenFavoriteUnavailable() {
        let store = makeStore()
        store.addFavorite(uid: "docking-station")
        let defaultDevice = device("built-in", name: "MacBook Mikrofon")

        let name = store.activeDeviceDisplayName(availableDevices: [defaultDevice], defaultDeviceID: defaultDevice.id)

        XCTAssertEqual(name, "MacBook Mikrofon")
    }

    func testFallsBackToPlaceholderWhenNothingResolves() {
        let store = makeStore()
        let name = store.activeDeviceDisplayName(availableDevices: [], defaultDeviceID: nil)
        XCTAssertEqual(name, "Mikrofon")
    }
}

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
