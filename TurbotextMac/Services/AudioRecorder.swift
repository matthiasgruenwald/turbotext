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

    private var outputFile: AVAudioFile?
    private var currentFileURL: URL?
    private var recordingStartedAt: Date?
    private var levelTimer: Timer?
    private var meteredPeakLevel: Float = -160
    private let defaults: PersistenceProvider
    private var diagnostics: RecordingDiagnostics?
    private var adapter: BufferFormatAdapter?
    private var directInput: DirectCoreAudioInput?
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
        // so a stale device selection never outlives the device.
        let targetDeviceID = Self.resolveTargetDeviceID(
            preferredUID: preferredInputDeviceUID(),
            availableDevices: MicrophoneService.availableInputDevices(),
            defaultDeviceID: MicrophoneService.defaultInputDeviceID()
        )
        guard let targetDeviceID, let direct = DirectCoreAudioInput(deviceID: targetDeviceID) else {
            errorMessage = "Kein Mikrofon verfügbar."
            return
        }
        startDirectRecording(direct, targetDeviceID: targetDeviceID)
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

    /// Opens the output file and per-recording state for the capture.
    private func beginSession(format: AVAudioFormat, targetDeviceID: AudioDeviceID?) -> Bool {
        let recordingFormat = AudioDownmix.recordingFormat(for: format)
        inputFormat = recordingFormat
        adapter = BufferFormatAdapter(targetFormat: recordingFormat)
        diagnostics = RecordingDiagnostics(
            requestedDeviceUID: preferredInputDeviceUID(),
            targetDeviceID: targetDeviceID,
            startFormat: format
        )
        let fileSettings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: recordingFormat.sampleRate,
            AVNumberOfChannelsKey: recordingFormat.channelCount,
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
        directInput?.stop()
        directInput = nil
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
        guard let recorded = AudioDownmix.forRecording(incoming),
              let adapted = adapter?.adapt(recorded) else {
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
