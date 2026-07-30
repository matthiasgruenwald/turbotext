import Foundation

struct LiveTranscriptCollector: Equatable {
    private(set) var finalText = ""
    private(set) var volatileText = ""

    var displayText: String {
        if volatileText.isEmpty { return finalText }
        if finalText.isEmpty { return volatileText }
        return finalText + " " + volatileText
    }

    var finalizedText: String {
        finalText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    mutating func apply(text: String, isFinal: Bool) {
        if isFinal {
            let separator = finalText.isEmpty ? "" : " "
            finalText += separator + text
            volatileText = ""
        } else {
            volatileText = text
        }
    }

    mutating func absorbVolatile() {
        guard !volatileText.isEmpty else { return }
        let separator = finalText.isEmpty ? "" : " "
        finalText += separator + volatileText
        volatileText = ""
    }
}
