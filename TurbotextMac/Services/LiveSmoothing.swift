import Foundation

protocol LiveSmoothing {
    func smooth(segment: String, context: String?) async -> String?
}

struct PassthroughSmoothing: LiveSmoothing {
    func smooth(segment: String, context: String?) async -> String? {
        segment
    }
}

enum LiveSmoothingContext {
    static func tail(of segment: String, maxLength: Int = 100) -> String? {
        let trimmed = segment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.count > maxLength else { return trimmed }
        return String(trimmed.suffix(maxLength))
    }
}
