import AVFoundation
import CoreAudio

/// Captures from one device through a CoreAudio IOProc, reading the device's real stream format.
final class DirectCoreAudioInput {
    let deviceID: AudioDeviceID
    let format: AVAudioFormat
    private let sourceIsInterleaved: Bool
    private var procID: AudioDeviceIOProcID?
    private var handler: (@Sendable (AVAudioPCMBuffer) -> Void)?

    init?(deviceID: AudioDeviceID) {
        guard let description = Self.inputStreamDescription(of: deviceID),
              let format = Self.makeFormat(from: description) else { return nil }
        self.deviceID = deviceID
        self.format = format
        sourceIsInterleaved = description.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0
    }

    func start(handler: @escaping @Sendable (AVAudioPCMBuffer) -> Void) -> OSStatus {
        self.handler = handler
        let format = format
        let interleaved = sourceIsInterleaved
        var newProcID: AudioDeviceIOProcID?
        let created = AudioDeviceCreateIOProcIDWithBlock(&newProcID, deviceID, nil) { [weak self] _, inData, _, _, _ in
            var list = inData.pointee
            guard let buffer = Self.makeBuffer(from: &list, format: format, sourceIsInterleaved: interleaved) else { return }
            self?.handler?(buffer)
        }
        guard created == noErr, let newProcID else { return created }
        procID = newProcID
        let started = AudioDeviceStart(deviceID, newProcID)
        if started != noErr { stop() }
        return started
    }

    func stop() {
        if let procID {
            AudioDeviceStop(deviceID, procID)
            AudioDeviceDestroyIOProcID(deviceID, procID)
        }
        procID = nil
        handler = nil
    }

    static func makeFormat(from description: AudioStreamBasicDescription) -> AVAudioFormat? {
        guard description.mFormatID == kAudioFormatLinearPCM,
              description.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              description.mBitsPerChannel == 32,
              description.mSampleRate > 0, description.mChannelsPerFrame > 0 else { return nil }
        guard let layout = AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_DiscreteInOrder | description.mChannelsPerFrame) else { return nil }
        return AVAudioFormat(standardFormatWithSampleRate: description.mSampleRate, channelLayout: layout)
    }

    static func makeBuffer(
        from list: UnsafePointer<AudioBufferList>,
        format: AVAudioFormat,
        sourceIsInterleaved: Bool
    ) -> AVAudioPCMBuffer? {
        let source = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: list))
        let channels = Int(format.channelCount)
        guard let first = source.first else { return nil }
        let frames = sourceIsInterleaved
            ? Int(first.mDataByteSize) / (MemoryLayout<Float>.size * max(1, Int(first.mNumberChannels)))
            : Int(first.mDataByteSize) / MemoryLayout<Float>.size
        guard frames > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)),
              let destination = buffer.floatChannelData else { return nil }
        buffer.frameLength = AVAudioFrameCount(frames)
        if sourceIsInterleaved {
            guard let data = first.mData?.assumingMemoryBound(to: Float.self) else { return nil }
            for channel in 0..<channels {
                for frame in 0..<frames { destination[channel][frame] = data[frame * channels + channel] }
            }
        } else {
            for channel in 0..<min(channels, source.count) {
                guard let data = source[channel].mData?.assumingMemoryBound(to: Float.self) else { return nil }
                destination[channel].update(from: data, count: frames)
            }
        }
        return buffer
    }

    private static func inputStreamDescription(of deviceID: AudioDeviceID) -> AudioStreamBasicDescription? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr, size >= 4 else { return nil }
        var streams = [AudioStreamID](repeating: 0, count: Int(size) / MemoryLayout<AudioStreamID>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &streams) == noErr,
              let stream = streams.first else { return nil }
        var formatAddress = AudioObjectPropertyAddress(
            mSelector: kAudioStreamPropertyVirtualFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var description = AudioStreamBasicDescription()
        var formatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        guard AudioObjectGetPropertyData(stream, &formatAddress, 0, nil, &formatSize, &description) == noErr else { return nil }
        return description
    }
}
