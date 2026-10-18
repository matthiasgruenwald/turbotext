import AVFoundation

/// Speech recording stays at mono/stereo: AAC files and `AVAudioFormat` without an explicit
/// channel layout do not support the 3-channel input of an open MacBook microphone array.
enum AudioDownmix {
    static let maxRecordedChannels: AVAudioChannelCount = 2

    static func recordingFormat(for input: AVAudioFormat) -> AVAudioFormat {
        guard input.channelCount > maxRecordedChannels else { return input }
        return AVAudioFormat(standardFormatWithSampleRate: input.sampleRate, channels: 1) ?? input
    }

    static func forRecording(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        let channels = Int(buffer.format.channelCount)
        guard channels > Int(maxRecordedChannels) else { return buffer }
        guard let source = buffer.floatChannelData,
              let mono = AVAudioFormat(standardFormatWithSampleRate: buffer.format.sampleRate, channels: 1),
              let output = AVAudioPCMBuffer(pcmFormat: mono, frameCapacity: buffer.frameLength),
              let destination = output.floatChannelData else { return nil }
        output.frameLength = buffer.frameLength
        let scale = 1 / Float(channels)
        for frame in 0..<Int(buffer.frameLength) {
            var sum: Float = 0
            for channel in 0..<channels { sum += source[channel][frame] }
            destination[0][frame] = sum * scale
        }
        return output
    }
}
