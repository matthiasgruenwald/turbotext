import XCTest
import AVFoundation
@testable import Turbotext

final class AudioDownmixTests: XCTestCase {

    private func wideFormat(channels: AVAudioChannelCount) -> AVAudioFormat {
        let layout = AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_DiscreteInOrder | channels)!
        return AVAudioFormat(standardFormatWithSampleRate: 48000, channelLayout: layout)
    }

    private func buffer(_ format: AVAudioFormat, values: [Float]) -> AVAudioPCMBuffer {
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4)!
        buffer.frameLength = 4
        for (channel, value) in values.enumerated() {
            for i in 0..<4 { buffer.floatChannelData![channel][i] = value }
        }
        return buffer
    }

    func testRecordingFormatKeepsMonoAndStereo() {
        let stereo = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        XCTAssertEqual(AudioDownmix.recordingFormat(for: stereo), stereo)
    }

    func testRecordingFormatReducesWideInputToMono() {
        let format = AudioDownmix.recordingFormat(for: wideFormat(channels: 3))
        XCTAssertEqual(format.channelCount, 1)
        XCTAssertEqual(format.sampleRate, 48000)
    }

    func testWideBufferIsAveragedToMono() throws {
        let input = buffer(wideFormat(channels: 3), values: [0.3, 0.6, 0.0])
        let output = try XCTUnwrap(AudioDownmix.forRecording(input))
        XCTAssertEqual(output.format.channelCount, 1)
        XCTAssertEqual(output.frameLength, 4)
        XCTAssertEqual(output.floatChannelData![0][0], 0.3, accuracy: 0.0001)
    }

    func testNarrowBufferPassesThroughUnchanged() throws {
        let stereo = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        let input = buffer(stereo, values: [0.2, 0.4])
        XCTAssertTrue(try XCTUnwrap(AudioDownmix.forRecording(input)) === input)
    }
}
