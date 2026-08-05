import Foundation

/// Why a local rewrite output was classified unusable before insertion (#179).
enum RewriteOutputFailure: Equatable {
    case promptEcho
    case noInputReference
    case fabrication
}

/// Pure classification of local (on-device) rewrite outputs. The on-device model
/// is known to answer weak transcripts with the system prompt verbatim, with a
/// rephrasing of it, or with fabricated text unrelated to the input (#175, #179);
/// any hit marks the output unusable.
enum RewriteOutputValidator {
    static let promptEchoMinimumRunLength = 30
    static let minimumContentWordLength = 4
    static let maximumOutputToInputRatio = 5

    static func validate(input: String, output: String, systemPrompt: String) -> RewriteOutputFailure? {
        if containsPromptEcho(output: output, systemPrompt: systemPrompt) { return .promptEcho }
        if lacksInputReference(input: input, output: output) { return .noInputReference }
        if isFabricated(input: input, output: output) { return .fabrication }
        return nil
    }

    static func containsPromptEcho(output: String, systemPrompt: String) -> Bool {
        let prompt = Array(systemPrompt)
        guard prompt.count >= promptEchoMinimumRunLength else { return false }
        for start in 0...(prompt.count - promptEchoMinimumRunLength) {
            let run = String(prompt[start..<start + promptEchoMinimumRunLength])
            if output.contains(run) { return true }
        }
        return false
    }

    static func contentWords(_ text: String) -> [String] {
        text.split { !$0.isLetter }
            .filter { $0.count >= minimumContentWordLength }
            .map(String.init)
    }

    static func lacksInputReference(input: String, output: String) -> Bool {
        let words = contentWords(input)
        guard !words.isEmpty else { return false }
        return !words.contains { output.range(of: $0, options: .caseInsensitive) != nil }
    }

    static func isFabricated(input: String, output: String) -> Bool {
        let inputLength = input.trimmingCharacters(in: .whitespacesAndNewlines).count
        let outputLength = output.trimmingCharacters(in: .whitespacesAndNewlines).count
        return outputLength > inputLength * maximumOutputToInputRatio
    }
}
