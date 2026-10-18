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
    private static let maxConfigurationRestarts = 5
    private var configurationRestarts = 0
    private var diagnostics: RecordingDiagnostics?
    private var adapter: BufferFormatAdapter?
    private var configObserver: NSObjectProtocol?
    private var directInput: DirectCoreAudioInput?
    private var engineActive = false
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
        configurationRestarts = 0
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
        if let targetDeviceID,
           AudioCaptureBackend.backend(forTransportType: MicrophoneService.transportType(of: targetDeviceID)) == .directCoreAudio,
           let direct = DirectCoreAudioInput(deviceID: targetDeviceID) {
            startDirectRecording(direct, targetDeviceID: targetDeviceID)
            return
        }
        startEngineRecording(targetDeviceID: targetDeviceID)
    }

    private func startDirectRecording(_ direct: DirectCoreAudioInput, targetDeviceID: AudioDeviceID) {
        guard beginSession(format: direct.format, targetDeviceID: targetDeviceID) else { return }
        let status = direct.start { [weak self] buffer in self?.handleBuffer(buffer) }
        guard status == noErr else {
            abortSession("Aufnahme konnte nicht gestartet werden (CoreAudio \(status)).")
            return
        }
        directInput = direct
        recordingStartedAt = Date()
        isRecording = true
        startMetering()
        withDiagnostics { $0.recordActualDevice(targetDeviceID) }
    }

    private func startEngineRecording(targetDeviceID: AudioDeviceID?) {
        if let targetDeviceID {
            setEngineInputDevice(targetDeviceID)
        }

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            errorMessage = "Kein Mikrofon verfügbar."
            return
        }
        guard beginSession(format: inputFormat, targetDeviceID: targetDeviceID) else { return }

        installTap(on: inputNode, format: inputFormat)

        do {
            engine.prepare()
            try engine.start()
            recordingStartedAt = Date()
            isRecording = true
            startMetering()
            engineActive = true
            observeConfigurationChanges(targetDeviceID: targetDeviceID)
            let actualID = actualEngineInputDeviceID()
            withDiagnostics { $0.recordActualDevice(actualID) }
        } catch {
            inputNode.removeTap(onBus: 0)
            abortSession("Aufnahme konnte nicht gestartet werden: \(error.localizedDescription)")
        }
    }

    /// Opens the output file and per-recording state shared by both capture backends.
    private func beginSession(format: AVAudioFormat, targetDeviceID: AudioDeviceID?) -> Bool {
        inputFormat = format
        adapter = BufferFormatAdapter(targetFormat: format)
        diagnostics = RecordingDiagnostics(
            requestedDeviceUID: preferredInputDeviceUID(),
            targetDeviceID: targetDeviceID,
            startFormat: format
        )
        let fileSettings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        let fileURL = makeRecordingURL()
        do {
            outputFile = try AVAudioFile(forWriting: fileURL, settings: fileSettings, commonFormat: .pcmFormatFloat32, interleaved: false)
            currentFileURL = fileURL
            return true
        } catch {
            currentFileURL = nil
            errorMessage = "Aufnahme konnte nicht gestartet werden: \(error.localizedDescription)"
            return false
        }
    }

    private func abortSession(_ message: String) {
        outputFile = nil
        currentFileURL = nil
        adapter = nil
        diagnostics = nil
        inputFormat = nil
        errorMessage = message
    }

    func stopRecording() {
        stopMetering()
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
        configObserver = nil
        directInput?.stop()
        directInput = nil
        if engineActive {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            engineActive = false
        }
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
            withDiagnostics { $0.recordConversionFailure() }
            return
        }
        let buffer = adapted.buffer
        meteredPeakLevel = Self.peakLevel(of: buffer)
        hasUsableSignal = hasUsableSignal || Self.isUsableSignal(meteredPeakLevel)
        let peak = meteredPeakLevel
        let rms = Self.rmsLevel(of: buffer)
        withDiagnostics { $0.recordBuffer(format: incoming.format, peakLevel: peak, rmsLevel: rms, converted: adapted.converted) }
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
        configurationRestarts += 1
        withDiagnostics { $0.recordConfigurationChange() }
        guard configurationRestarts <= Self.maxConfigurationRestarts else {
            failRecording("Aufnahme wiederholt unterbrochen (Audiogerät wechselt ständig).")
            return
        }
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
            failRecording("Kein Mikrofon verfügbar.")
            return
        }
        installTap(on: inputNode, format: newFormat)
        engine.prepare()
        do {
            try engine.start()
        } catch {
            failRecording("Aufnahme konnte nicht fortgesetzt werden: \(error.localizedDescription)")
        }
        let actualID = actualEngineInputDeviceID()
        withDiagnostics { $0.recordActualDevice(actualID) }
    }

    /// Leaves stopping to the owning pipeline so its recording state stays consistent.
    private func failRecording(_ message: String) {
        errorMessage = message
    }

    private func installTap(on inputNode: AVAudioInputNode, format: AVAudioFormat) {
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            self?.handleBuffer(buffer)
        }
    }

    private func actualEngineInputDeviceID() -> AudioDeviceID? {
        guard let inputUnit = engine.inputNode.audioUnit else { return nil }
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioUnitGetProperty(inputUnit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &deviceID, &size)
        return status == noErr ? deviceID : nil
    }

    static func isUsableSignal(_ peakLevel: Float) -> Bool {
        peakLevel > usableSignalThreshold
    }

    private static func rmsLevel(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData, buffer.frameLength > 0 else { return -160 }
        let frames = Int(buffer.frameLength)
        var sum: Float = 0
        for sample in 0..<frames { sum += channelData[0][sample] * channelData[0][sample] }
        let rms = (sum / Float(frames)).squareRoot()
        return rms > 0 ? 20 * log10(rms) : -160
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
