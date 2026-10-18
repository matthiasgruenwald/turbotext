import AVFoundation
import CoreAudio
import OSLog

private let recordingLogger = Logger(subsystem: "app.turbotext.mac", category: "Recording")

struct RecordingDiagnostics {
    struct Format: Equatable {
        let sampleRate: Double
        let channelCount: UInt32

        init(_ format: AVAudioFormat) {
            sampleRate = format.sampleRate
            channelCount = format.channelCount
        }
    }

    let requestedDeviceUID: String?
    let targetDeviceID: AudioDeviceID?
    let startFormat: Format
    private(set) var bufferCount = 0
    private(set) var peakLevel: Float = -160
    private(set) var configurationChanges = 0
    private(set) var convertedBuffers = 0
    private(set) var writeFailures = 0
    private(set) var formatsSeen: [Format]

    init(requestedDeviceUID: String?, targetDeviceID: AudioDeviceID?, startFormat: AVAudioFormat) {
        self.requestedDeviceUID = requestedDeviceUID
        self.targetDeviceID = targetDeviceID
        self.startFormat = Format(startFormat)
        formatsSeen = [Format(startFormat)]
    }

    mutating func recordBuffer(format: AVAudioFormat, peakLevel: Float, converted: Bool) {
        bufferCount += 1
        self.peakLevel = max(self.peakLevel, peakLevel)
        if converted { convertedBuffers += 1 }
        let seen = Format(format)
        if !formatsSeen.contains(seen) { formatsSeen.append(seen) }
    }

    mutating func recordConfigurationChange() { configurationChanges += 1 }
    mutating func recordWriteFailure() { writeFailures += 1 }

    var hasUsableSignal: Bool { AudioRecorder.isUsableSignal(peakLevel) }

    var verdict: String {
        if bufferCount == 0 { return "RED: no buffers delivered" }
        if writeFailures > 0 { return "RED: \(writeFailures) write failures" }
        if !hasUsableSignal { return "RED: silent (peak \(Int(peakLevel)) dB)" }
        return "GREEN"
    }

    var summary: String {
        let formats = formatsSeen.map { "\(Int($0.sampleRate))Hz/\($0.channelCount)ch" }.joined(separator: ",")
        return "device=\(requestedDeviceUID ?? "default") id=\(targetDeviceID.map(String.init) ?? "nil") "
            + "startFormat=\(Int(startFormat.sampleRate))Hz/\(startFormat.channelCount)ch formatsSeen=[\(formats)] "
            + "buffers=\(bufferCount) converted=\(convertedBuffers) configChanges=\(configurationChanges) "
            + "peak=\(peakLevel)dB verdict=\(verdict)"
    }

    func log() {
        if verdict == "GREEN" {
            recordingLogger.info("Recording finished: \(summary, privacy: .public)")
        } else {
            recordingLogger.error("Recording finished: \(summary, privacy: .public)")
        }
    }
}

/// Converts buffers from a changed hardware format (e.g. Bluetooth switching to the
/// headset profile) back to the format the recording started with.
final class BufferFormatAdapter {
    let targetFormat: AVAudioFormat
    private var converter: AVAudioConverter?

    init(targetFormat: AVAudioFormat) {
        self.targetFormat = targetFormat
    }

    func adapt(_ buffer: AVAudioPCMBuffer) -> (buffer: AVAudioPCMBuffer, converted: Bool)? {
        guard buffer.format != targetFormat else { return (buffer, false) }
        if converter?.inputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: targetFormat)
        }
        guard let converter else { return nil }
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 16
        guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return nil }
        var supplied = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if supplied {
                inputStatus.pointee = .noDataNow
                return nil
            }
            supplied = true
            inputStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, error == nil else { return nil }
        return (output, true)
    }
}
