import XCTest
import CoreAudio
import Observation
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

    func testDeviceAvailabilityUpdatesWhenSelectedMicrophoneStaysTheSame() {
        let persistence = InMemoryPersistence()
        let favorites = MicrophoneFavoritesStore(defaults: persistence)
        favorites.addFavorite(uid: "built-in")
        favorites.addFavorite(uid: "usb")
        let builtIn = AudioInputDevice(id: 1, name: "Internal Microphone", uid: "built-in")
        let usb = AudioInputDevice(id: 2, name: "USB Microphone", uid: "usb")
        var devices = [builtIn, usb]
        let state = MicrophoneState(
            favoritesStore: favorites,
            deviceProvider: { devices },
            defaultDeviceIDProvider: { builtIn.id },
            persistence: persistence
        )
        state.refreshDevices()
        let availabilityChanged = expectation(description: "Device availability changes")
        withObservationTracking {
            _ = state.availableDevices
        } onChange: {
            availabilityChanged.fulfill()
        }

        devices = [builtIn]
        state.refreshDevices()

        wait(for: [availabilityChanged], timeout: 1)
        XCTAssertEqual(state.availableDevices, [builtIn])
        XCTAssertEqual(state.activeMicrophone, ActiveMicrophone(uid: "built-in", source: .favorite))
        XCTAssertEqual(state.favorites, ["built-in", "usb"])
        XCTAssertEqual(state.favoritesStore.displayName(forUID: "usb"), "USB Microphone")

        devices = [builtIn, usb]
        state.refreshDevices()
        XCTAssertEqual(state.availableDevices, [builtIn, usb])
    }
}
