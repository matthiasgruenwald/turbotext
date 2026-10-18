import XCTest
import AVFoundation
import CoreAudio
@testable import Turbotext

final class DirectCoreAudioInputTests: XCTestCase {

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

    func testInputCallbackCopiesSeparateChannelBuffers() throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2))
        let source = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4))
        source.frameLength = 4
        source.floatChannelData![0].initialize(repeating: 0.25, count: 4)
        source.floatChannelData![1].initialize(repeating: 0.75, count: 4)
        XCTAssertEqual(source.audioBufferList.pointee.mNumberBuffers, 2)
        let received = expectation(description: "Both channel buffers reach the recording handler")
        let callback = DirectCoreAudioInput.inputCallback(format: format, sourceIsInterleaved: false) { buffer in
            XCTAssertEqual(buffer.frameLength, 4)
            XCTAssertEqual(buffer.floatChannelData![0][0], 0.25)
            XCTAssertEqual(buffer.floatChannelData![1][3], 0.75)
            received.fulfill()
        }
        var timestamp = AudioTimeStamp()
        var output = AudioBufferList()

        withUnsafePointer(to: &timestamp) { time in
            callback(time, source.audioBufferList, time, &output, time)
        }

        wait(for: [received], timeout: 1)
    }

    func testWideInputGetsFormatWithChannelLayout() {
        var description = AudioStreamBasicDescription(
            mSampleRate: 48000, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 12, mFramesPerPacket: 1, mBytesPerFrame: 12,
            mChannelsPerFrame: 3, mBitsPerChannel: 32, mReserved: 0
        )
        XCTAssertEqual(DirectCoreAudioInput.makeFormat(from: description)?.channelCount, 3)
        description.mChannelsPerFrame = 1
        XCTAssertEqual(DirectCoreAudioInput.makeFormat(from: description)?.channelCount, 1)
    }
}
