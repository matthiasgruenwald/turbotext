import Foundation

protocol SpokenWorkflowRecording: AnyObject {
    var isRecording: Bool { get }
    var recordingURL: URL? { get }
    var errorMessage: String? { get }
    var audioLevel: Float { get }
    var lastRecordingDuration: TimeInterval { get }

    func startRecording()
    func stopRecording()
    func discardRecording()
}

extension AudioRecorder: SpokenWorkflowRecording {}

@MainActor
final class SpokenWorkflowPipeline {
    struct Recording: Equatable {
        let url: URL
        let duration: TimeInterval
    }

    enum Error: Swift.Error, Equatable, LocalizedError {
        case noRecording
        case noSpeech

        var errorDescription: String? {
            switch self {
            case .noRecording:
                return "Keine Aufnahme vorhanden."
            case .noSpeech:
                return "Keine Aufnahme erkannt."
            }
        }
    }

    typealias Transcriber = (URL, TimeInterval, [String], String) async throws -> String

    private let recorder: any SpokenWorkflowRecording

    init(recorder: any SpokenWorkflowRecording = AudioRecorder()) {
        self.recorder = recorder
    }

    var isRecording: Bool { recorder.isRecording }
    var audioLevel: Float { recorder.audioLevel }

    func startRecording() -> Result<Void, Swift.Error> {
        recorder.startRecording()
        if let error = recorder.errorMessage {
            return .failure(NSError(domain: "Turbotext", code: 1, userInfo: [NSLocalizedDescriptionKey: error]))
        }
        return .success(())
    }

    func stopRecording() -> Result<Recording, Error> {
        recorder.stopRecording()
        guard !TranscriptionQualityService.shouldRejectRecording(duration: recorder.lastRecordingDuration) else {
            recorder.discardRecording()
            return .failure(.noSpeech)
        }
        guard let url = recorder.recordingURL else {
            return .failure(.noRecording)
        }
        return .success(Recording(url: url, duration: recorder.lastRecordingDuration))
    }

    func resetRecording() {
        if recorder.isRecording {
            recorder.stopRecording()
        }
        recorder.discardRecording()
    }

    func transcribeRecording(
        _ recording: Recording,
        customTerms: [String],
        language: String,
        transcriber: Transcriber
    ) async throws -> String {
        defer {
            try? FileManager.default.removeItem(at: recording.url)
        }

        let terms = recording.duration >= 0.9 ? customTerms : []
        let rawText = try await transcriber(recording.url, recording.duration, terms, language)
        let cleaned = TranscriptionQualityService.cleanedTranscript(rawText)
        guard !TranscriptionQualityService.isLikelyArtifact(cleaned, recordingDuration: recording.duration) else {
            throw Error.noSpeech
        }
        return cleaned
    }
}
