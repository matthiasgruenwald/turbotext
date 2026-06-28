import XCTest
import CoreAudio
@testable import Turbotext

final class AudioRecorderDeviceSelectionTests: XCTestCase {

    private func device(_ uid: String) -> AudioInputDevice {
        AudioInputDevice(id: AudioDeviceID(abs(uid.hashValue) % Int(UInt32.max)), name: uid, uid: uid)
    }

    func testUsesPreferredDeviceWhenAvailable() {
        let preferred = device("usb-mic")
        let resolved = AudioRecorder.resolveTargetDeviceID(
            preferredUID: "usb-mic",
            availableDevices: [preferred, device("built-in")],
            defaultDeviceID: device("built-in").id
        )
        XCTAssertEqual(resolved, preferred.id)
    }

    func testFallsBackToSystemDefaultWhenPreferredDeviceIsGone() {
        let builtIn = device("built-in")
        let resolved = AudioRecorder.resolveTargetDeviceID(
            preferredUID: "usb-mic",
            availableDevices: [builtIn],
            defaultDeviceID: builtIn.id
        )
        XCTAssertEqual(resolved, builtIn.id)
    }

    func testFallsBackToSystemDefaultWhenNoPreferredUID() {
        let builtIn = device("built-in")
        let resolved = AudioRecorder.resolveTargetDeviceID(
            preferredUID: nil,
            availableDevices: [builtIn],
            defaultDeviceID: builtIn.id
        )
        XCTAssertEqual(resolved, builtIn.id)
    }

    func testReturnsNilWhenNothingResolves() {
        let resolved = AudioRecorder.resolveTargetDeviceID(
            preferredUID: "usb-mic",
            availableDevices: [],
            defaultDeviceID: nil
        )
        XCTAssertNil(resolved)
    }
}
