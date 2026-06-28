import Foundation

/// Builds an OpenAI-compatible multipart/form-data request body for audio
/// transcription endpoints (used by both Groq and OpenAI transcription paths).
enum MultipartFormDataBuilder {
    static func build(
        boundary: String,
        audioData: Data,
        filename: String,
        mimeType: String,
        model: String,
        responseFormat: String,
        prompt: String?,
        language: String?
    ) -> Data {
        var body = Data()

        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
        body.append("Content-Type: \(mimeType)\r\n\r\n")
        body.append(audioData)
        body.append("\r\n")

        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n")
        body.append(model)
        body.append("\r\n")

        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n")
        body.append(responseFormat)
        body.append("\r\n")

        if let prompt, !prompt.isEmpty {
            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"prompt\"\r\n\r\n")
            body.append(prompt)
            body.append("\r\n")
        }

        if let language, !language.isEmpty {
            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n")
            body.append(language)
            body.append("\r\n")
        }

        body.append("--\(boundary)--\r\n")
        return body
    }
}

extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
