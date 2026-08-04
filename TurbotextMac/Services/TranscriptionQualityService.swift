import Foundation

enum TranscriptionQualityService {
    static let minimumRecordingDuration: TimeInterval = 0.3

    /// Shortest transcript the rewrite workflows will send to an LLM. Fed a single
    /// leftover character, the on-device model echoes the system prompt back out
    /// instead of improving anything (#175), so anything below a minimal word is
    /// treated as "no speech" before it ever reaches a model.
    static let minimumRewriteLength = 2

    /// Longest transcript the rewrite workflows insert raw instead of sending
    /// to an LLM (#173): fed 2–4 characters, the on-device model hallucinates
    /// or echoes the system prompt, so such fragments are pasted untouched.
    static let rawInsertionMaxLength = 4

    static func shouldRejectRecording(duration: TimeInterval) -> Bool {
        duration < minimumRecordingDuration
    }

    static func cleanedTranscript(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func isTooShortToRewrite(_ text: String) -> Bool {
        cleanedTranscript(text).count < minimumRewriteLength
    }

    static func isShortEnoughForRawInsertion(_ text: String) -> Bool {
        cleanedTranscript(text).count <= rawInsertionMaxLength
    }

    static func isLikelyArtifact(_ text: String, recordingDuration: TimeInterval) -> Bool {
        let cleaned = cleanedTranscript(text)
        guard !cleaned.isEmpty else { return true }

        let words = cleaned.split { $0.isWhitespace || $0.isNewline }
        let letters = cleaned.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count

        if letters == 0 {
            return true
        }

        if recordingDuration < 0.55 && (words.count >= 5 || cleaned.count >= 32) {
            return true
        }

        if recordingDuration < 0.8 && cleaned.count >= 56 {
            return true
        }

        return false
    }
}
