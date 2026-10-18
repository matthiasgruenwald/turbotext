import XCTest
import AVFoundation
import CoreAudio
@testable import Turbotext

final class DirectCoreAudioInputTests: XCTestCase {

    func testBluetoothTransportsUseDirectBackend() {
        XCTAssertEqual(AudioCaptureBackend.backend(forTransportType: kAudioDeviceTransportTypeBluetooth), .directCoreAudio)
        XCTAssertEqual(AudioCaptureBackend.backend(forTransportType: kAudioDeviceTransportTypeBluetoothLE), .directCoreAudio)
    }

    func testOtherTransportsKeepAudioEngine() {
        XCTAssertEqual(AudioCaptureBackend.backend(forTransportType: kAudioDeviceTransportTypeUSB), .audioEngine)
        XCTAssertEqual(AudioCaptureBackend.backend(forTransportType: kAudioDeviceTransportTypeBuiltIn), .audioEngine)
        XCTAssertEqual(AudioCaptureBackend.backend(forTransportType: nil), .audioEngine)
    }

    func testFormatFromFloat32MonoStream() throws {
        let asbd = AudioStreamBasicDescription(
            mSampleRate: 16000, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4,
            mChannelsPerFrame: 1, mBitsPerChannel: 32, mReserved: 0
        )
        let format = try XCTUnwrap(DirectCoreAudioInput.makeFormat(from: asbd))
        XCTAssertEqual(format.sampleRate, 16000)
        XCTAssertEqual(format.channelCount, 1)
        XCTAssertEqual(format.commonFormat, .pcmFormatFloat32)
        XCTAssertFalse(format.isInterleaved)
    }

    func testRejectsNonFloatStream() {
        let asbd = AudioStreamBasicDescription(
            mSampleRate: 16000, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2,
            mChannelsPerFrame: 1, mBitsPerChannel: 16, mReserved: 0
        )
        XCTAssertNil(DirectCoreAudioInput.makeFormat(from: asbd))
    }

    func testCopiesInterleavedStereoIntoNonInterleavedBuffer() throws {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48000, channels: 2, interleaved: false)!
        var samples: [Float] = [0.1, 0.9, 0.2, 0.8, 0.3, 0.7]
        let buffer = samples.withUnsafeMutableBytes { raw -> AVAudioPCMBuffer? in
            var list = AudioBufferList(
                mNumberBuffers: 1,
                mBuffers: AudioBuffer(mNumberChannels: 2, mDataByteSize: UInt32(raw.count), mData: raw.baseAddress)
            )
            return DirectCoreAudioInput.makeBuffer(from: &list, format: format, sourceIsInterleaved: true)
        }
        let result = try XCTUnwrap(buffer)
        XCTAssertEqual(result.frameLength, 3)
        XCTAssertEqual(result.floatChannelData![0][1], 0.2)
        XCTAssertEqual(result.floatChannelData![1][2], 0.7)
    }

    func testCopiesMonoBuffer() throws {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
        var samples: [Float] = [0.5, -0.5, 0.25, 0]
        let buffer = samples.withUnsafeMutableBytes { raw -> AVAudioPCMBuffer? in
            var list = AudioBufferList(
                mNumberBuffers: 1,
                mBuffers: AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(raw.count), mData: raw.baseAddress)
            )
            return DirectCoreAudioInput.makeBuffer(from: &list, format: format, sourceIsInterleaved: true)
        }
        XCTAssertEqual(try XCTUnwrap(buffer).frameLength, 4)
        XCTAssertEqual(buffer?.floatChannelData![0][1], -0.5)
    }
}
