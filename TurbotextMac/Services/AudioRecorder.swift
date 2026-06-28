import AVFoundation
import AudioToolbox
import CoreAudio
import Observation

@Observable
final class AudioRecorder: NSObject {
    var isRecording = false
    var recordingURL: URL?
    var errorMessage: String?
    var audioLevel: Float = 0
    var lastRecordingDuration: TimeInterval = 0

    private let engine = AVAudioEngine()
    private var outputFile: AVAudioFile?
    private var currentFileURL: URL?
    private var recordingStartedAt: Date?
    private var levelTimer: Timer?
    private var meteredPeakLevel: Float = -160

    private func makeRecordingURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("turbotext-\(UUID().uuidString).m4a")
    }

    func startRecording() {
        errorMessage = nil
        lastRecordingDuration = 0
        recordingURL = nil
        if let currentFileURL {
            try? FileManager.default.removeItem(at: currentFileURL)
        }

        // App-internal device selection only: routes this recording to the preferred
        // input device without touching the macOS-wide default input (see ADR-0003).
        // Falls back to the system default device when the preferred device is gone,
        // so a stale device pinning from a previous recording never lingers on the engine.
        let targetDeviceID = Self.resolveTargetDeviceID(
            preferredUID: preferredInputDeviceUID(),
            availableDevices: MicrophoneService.availableInputDevices(),
            defaultDeviceID: MicrophoneService.defaultInputDeviceID()
        )
        if let targetDeviceID {
            setEngineInputDevice(targetDeviceID)
        }

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            errorMessage = "Kein Mikrofon verfügbar."
            return
        }

        let fileSettings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: inputFormat.sampleRate,
            AVNumberOfChannelsKey: inputFormat.channelCount,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]

        let fileURL = makeRecordingURL()
        do {
            let file = try AVAudioFile(forWriting: fileURL, settings: fileSettings, commonFormat: .pcmFormatFloat32, interleaved: false)
            outputFile = file
            currentFileURL = fileURL
        } catch {
            currentFileURL = nil
            errorMessage = "Aufnahme konnte nicht gestartet werden: \(error.localizedDescription)"
            return
        }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.handleBuffer(buffer)
        }

        do {
            engine.prepare()
            try engine.start()
            recordingStartedAt = Date()
            isRecording = true
            startMetering()
        } catch {
            inputNode.removeTap(onBus: 0)
            outputFile = nil
            currentFileURL = nil
            errorMessage = "Aufnahme konnte nicht gestartet werden: \(error.localizedDescription)"
        }
    }

    func stopRecording() {
        stopMetering()
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        if let recordingStartedAt {
            lastRecordingDuration = Date().timeIntervalSince(recordingStartedAt)
        }
        self.recordingStartedAt = nil
        outputFile = nil
        isRecording = false
        recordingURL = currentFileURL
        currentFileURL = nil
        audioLevel = 0
    }

    func discardRecording() {
        if let recordingURL {
            try? FileManager.default.removeItem(at: recordingURL)
            self.recordingURL = nil
        }

        if let currentFileURL {
            try? FileManager.default.removeItem(at: currentFileURL)
            self.currentFileURL = nil
        }
    }

    private func handleBuffer(_ buffer: AVAudioPCMBuffer) {
        meteredPeakLevel = Self.peakLevel(of: buffer)
        try? outputFile?.write(from: buffer)
    }

    private static func peakLevel(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return -160 }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return -160 }
        var peak: Float = 0
        for sample in 0..<frameCount {
            peak = max(peak, abs(channelData[0][sample]))
        }
        guard peak > 0 else { return -160 }
        return 20 * log10(peak)
    }

    /// Pure resolution: prefers the available device matching `preferredUID`,
    /// otherwise falls back to the system default input device.
    static func resolveTargetDeviceID(
        preferredUID: String?,
        availableDevices: [AudioInputDevice],
        defaultDeviceID: AudioDeviceID?
    ) -> AudioDeviceID? {
        if let preferredUID, let match = availableDevices.first(where: { $0.uid == preferredUID }) {
            return match.id
        }
        return defaultDeviceID
    }

    private func preferredInputDeviceUID() -> String? {
        UserDefaults.standard.string(forKey: "selectedMicUID").flatMap { $0.isEmpty ? nil : $0 }
    }

    private func setEngineInputDevice(_ deviceID: AudioDeviceID) {
        guard let inputUnit = engine.inputNode.audioUnit else { return }
        var mutableDeviceID = deviceID
        AudioUnitSetProperty(
            inputUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &mutableDeviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
    }

    private func startMetering() {
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self else { return }
            let normalized = max(0, min(1, (self.meteredPeakLevel + 50) / 50))
            self.audioLevel = normalized
        }
    }

    private func stopMetering() {
        levelTimer?.invalidate()
        levelTimer = nil
    }
}
