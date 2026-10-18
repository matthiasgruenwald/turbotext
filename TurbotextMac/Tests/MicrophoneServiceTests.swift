import CoreAudio
import XCTest
@testable import Turbotext

final class MicrophoneServiceTests: XCTestCase {
    func testExcludesVirtualAndAggregateTransports() {
        XCTAssertFalse(MicrophoneService.isSelectableTransport(kAudioDeviceTransportTypeVirtual))
        XCTAssertFalse(MicrophoneService.isSelectableTransport(kAudioDeviceTransportTypeAggregate))
    }

    func testKeepsPhysicalContinuityAndUnknownTransportsSelectable() {
        let transports: [UInt32] = [
            kAudioDeviceTransportTypeBuiltIn,
            kAudioDeviceTransportTypeUSB,
            kAudioDeviceTransportTypeBluetooth,
            kAudioDeviceTransportTypeBluetoothLE,
            0x63637764,
            kAudioDeviceTransportTypeUnknown,
            0x12345678
        ]

        for transport in transports {
            XCTAssertTrue(MicrophoneService.isSelectableTransport(transport), "Transport: \(transport)")
        }
    }
}
