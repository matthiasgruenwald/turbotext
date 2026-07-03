import XCTest
import CoreAudio
@testable import Turbotext

final class MicrophoneResolutionTests: XCTestCase {

    private func device(_ uid: String, name: String? = nil) -> AudioInputDevice {
        AudioInputDevice(id: AudioDeviceID(abs(uid.hashValue) % Int(UInt32.max)), name: name ?? uid, uid: uid)
    }

    func testResolvesHighestPriorityAvailableFavorite() {
        let available = [device("built-in"), device("docking-station-B")]

        let result = MicrophoneResolution.resolve(
            favoriteUIDs: ["docking-station-A", "docking-station-B", "built-in"],
            useSystemDefault: false,
            availableDevices: available,
            systemDefaultDeviceID: nil
        )

        XCTAssertEqual(result, ActiveMicrophone(uid: "docking-station-B", source: .favorite))
    }

    func testFallsBackToSystemDefaultWhenNoFavoriteAvailable() {
        let defaultDevice = device("built-in")

        let result = MicrophoneResolution.resolve(
            favoriteUIDs: ["docking-station-A"],
            useSystemDefault: false,
            availableDevices: [defaultDevice],
            systemDefaultDeviceID: defaultDevice.id
        )

        XCTAssertEqual(result, ActiveMicrophone(uid: "built-in", source: .systemDefault))
    }

    func testFallsBackToSystemDefaultWhenUseSystemDefaultEnabledEvenIfFavoriteAvailable() {
        let favoriteDevice = device("built-in")

        let result = MicrophoneResolution.resolve(
            favoriteUIDs: ["built-in"],
            useSystemDefault: true,
            availableDevices: [favoriteDevice],
            systemDefaultDeviceID: favoriteDevice.id
        )

        XCTAssertEqual(result, ActiveMicrophone(uid: "built-in", source: .systemDefault))
    }

    func testResolvesNilUIDWhenNothingAvailable() {
        let result = MicrophoneResolution.resolve(
            favoriteUIDs: ["docking-station-A"],
            useSystemDefault: false,
            availableDevices: [],
            systemDefaultDeviceID: nil
        )

        XCTAssertEqual(result, ActiveMicrophone(uid: nil, source: .systemDefault))
    }

    func testResolvesNilUIDWhenFavoritesEmptyAndNoSystemDefaultMatch() {
        let result = MicrophoneResolution.resolve(
            favoriteUIDs: [],
            useSystemDefault: false,
            availableDevices: [device("built-in")],
            systemDefaultDeviceID: nil
        )

        XCTAssertEqual(result, ActiveMicrophone(uid: nil, source: .systemDefault))
    }
}
