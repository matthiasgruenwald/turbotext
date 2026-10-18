import AppKit
import AVFoundation
import AudioToolbox
import CoreAudio
import Observation

@Observable
final class AudioRecorder: NSObject {
    static let usableSignalThreshold: Float = -47.5

    var isRecording = false
    var recordingURL: URL?
    var errorMessage: String?
    var audioLevel: Float = 0
    private(set) var hasUsableSignal = false
    var lastRecordingDuration: TimeInterval = 0
    var onBuffer: (@Sendable (AVAudioPCMBuffer) -> Void)?
    private(set) var inputFormat: AVAudioFormat?

    private let engine = AVAudioEngine()
    private var outputFile: AVAudioFile?
    private var currentFileURL: URL?
    private var recordingStartedAt: Date?
    private var levelTimer: Timer?
    private var meteredPeakLevel: Float = -160
    private let defaults: PersistenceProvider
    private var diagnostics: RecordingDiagnostics?
    private var adapter: BufferFormatAdapter?
    private var configObserver: NSObjectProtocol?
    private let diagnosticsLock = NSLock()

    init(defaults: PersistenceProvider = UserDefaultsPersistence.shared) {
        self.defaults = defaults
        super.init()
    }

    private func makeRecordingURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("turbotext-\(UUID().uuidString).m4a")
    }

    func startRecording() {
        errorMessage = nil
        lastRecordingDuration = 0
        recordingURL = nil
        hasUsableSignal = false
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
        self.inputFormat = inputFormat
        adapter = BufferFormatAdapter(targetFormat: inputFormat)
        diagnostics = RecordingDiagnostics(
            requestedDeviceUID: preferredInputDeviceUID(),
            targetDeviceID: targetDeviceID,
            startFormat: inputFormat
        )

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
            observeConfigurationChanges(targetDeviceID: targetDeviceID)
        } catch {
            inputNode.removeTap(onBus: 0)
            outputFile = nil
            currentFileURL = nil
            errorMessage = "Aufnahme konnte nicht gestartet werden: \(error.localizedDescription)"
        }
    }

    func stopRecording() {
        stopMetering()
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
        configObserver = nil
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        withDiagnostics { $0.log() }
        diagnostics = nil
        adapter = nil
        if let recordingStartedAt {
            lastRecordingDuration = Date().timeIntervalSince(recordingStartedAt)
        }
        self.recordingStartedAt = nil
        outputFile = nil
        isRecording = false
        recordingURL = currentFileURL
        currentFileURL = nil
        audioLevel = 0
        inputFormat = nil
        onBuffer = nil
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

    private func handleBuffer(_ incoming: AVAudioPCMBuffer) {
        guard let adapted = adapter?.adapt(incoming) else {
            withDiagnostics { $0.recordWriteFailure() }
            return
        }
        let buffer = adapted.buffer
        meteredPeakLevel = Self.peakLevel(of: buffer)
        hasUsableSignal = hasUsableSignal || Self.isUsableSignal(meteredPeakLevel)
        let peak = meteredPeakLevel
        withDiagnostics { $0.recordBuffer(format: incoming.format, peakLevel: peak, converted: adapted.converted) }
        do {
            try outputFile?.write(from: buffer)
        } catch {
            withDiagnostics { $0.recordWriteFailure() }
        }
        onBuffer?(buffer)
    }

    private func withDiagnostics(_ body: (inout RecordingDiagnostics) -> Void) {
        diagnosticsLock.lock()
        defer { diagnosticsLock.unlock() }
        guard var current = diagnostics else { return }
        body(&current)
        diagnostics = current
    }

    /// Bluetooth profile switches and other apps (e.g. a video conference) claiming the
    /// device stop the engine and change the input format; re-tap with the new format and restart.
    private func observeConfigurationChanges(targetDeviceID: AudioDeviceID?) {
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            self?.restartAfterConfigurationChange(targetDeviceID: targetDeviceID)
        }
    }

    private func restartAfterConfigurationChange(targetDeviceID: AudioDeviceID?) {
        guard isRecording else { return }
        withDiagnostics { $0.recordConfigurationChange() }
        let inputNode = engine.inputNode
        inputNode.removeTap(onBus: 0)
        engine.stop()
        let refreshedTarget = Self.resolveTargetDeviceID(
            preferredUID: preferredInputDeviceUID(),
            availableDevices: MicrophoneService.availableInputDevices(),
            defaultDeviceID: MicrophoneService.defaultInputDeviceID()
        ) ?? targetDeviceID
        if let refreshedTarget { setEngineInputDevice(refreshedTarget) }
        let newFormat = inputNode.outputFormat(forBus: 0)
        guard newFormat.sampleRate > 0, newFormat.channelCount > 0 else {
            errorMessage = "Kein Mikrofon verfügbar."
            return
        }
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: newFormat) { [weak self] buffer, _ in
            self?.handleBuffer(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            errorMessage = "Aufnahme konnte nicht fortgesetzt werden: \(error.localizedDescription)"
        }
    }

    static func isUsableSignal(_ peakLevel: Float) -> Bool {
        peakLevel > usableSignalThreshold
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

    /// Reads the shared `selectedMicUID` key owned and written by `MicrophoneAutoSelectionService`.
    /// `AudioRecorder` never writes this key itself.
    private func preferredInputDeviceUID() -> String? {
        defaults.string(forKey: "selectedMicUID").flatMap { $0.isEmpty ? nil : $0 }
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
