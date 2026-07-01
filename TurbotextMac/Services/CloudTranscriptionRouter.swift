import Foundation

private struct TranscriptionOpenAIErrorResponse: Decodable {
    struct APIError: Decodable {
        let message: String?
    }
    let error: APIError?
}

struct CloudTranscriptionRouter {
    typealias GroqTranscribe = (URL, String, [String], String?) async throws -> (text: String, rateLimitInfo: GroqRateLimitInfo)
    typealias OpenAITranscribe = (URL, [String], String?) async throws -> String
    typealias GroqQuotaCheck = (String) async throws -> GroqRateLimitInfo
    typealias GroqKeyLoader = () -> String?

    private static let remoteModel = "gpt-4o-mini-transcribe"
    private static let transcriptionsURL = URL(string: "https://api.openai.com/v1/audio/transcriptions")!

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 60
        return URLSession(configuration: configuration)
    }()

    private let groqKey: GroqKeyLoader
    private let groqTranscribe: GroqTranscribe
    private let openAITranscribe: OpenAITranscribe
    private let groqQuotaCheck: GroqQuotaCheck

    init(
        groqKey: @escaping GroqKeyLoader = { KeychainService.load(key: .groqAPIKey) },
        groqTranscribe: @escaping GroqTranscribe = GroqTranscriptionService.transcribe,
        openAITranscribe: @escaping OpenAITranscribe = CloudTranscriptionRouter.defaultOpenAITranscribe,
        groqQuotaCheck: @escaping GroqQuotaCheck = GroqTranscriptionService.checkQuota
    ) {
        self.groqKey = groqKey
        self.groqTranscribe = groqTranscribe
        self.openAITranscribe = openAITranscribe
        self.groqQuotaCheck = groqQuotaCheck
    }

    func transcribe(
        audioURL: URL,
        durationSeconds: TimeInterval,
        customTerms: [String] = [],
        language: String? = nil
    ) async throws -> TranscriptionOutcome {
        let fallbackWasActive = await MainActor.run { GroqQuotaStore.shared.fallbackActive }

        if let groqKey = groqKey(), !fallbackWasActive {
            do {
                let (text, info) = try await groqTranscribe(audioURL, groqKey, customTerms, language)
                await updateQuota(info: info, durationSeconds: durationSeconds)
                return .success(text)
            } catch GroqTranscriptionError.rateLimitExceeded(let resetAt) {
                await MainActor.run { GroqQuotaStore.shared.activateFallback(resetAt: resetAt) }
                let text = try await openAITranscribe(audioURL, customTerms, language)
                return .fallbackActivated(text)
            }
        }

        let text = try await openAITranscribe(audioURL, customTerms, language)
        return fallbackWasActive ? .fallbackActivated(text) : .success(text)
    }

    func checkGroqQuotaIfNeeded(secureLocalModeEnabled: Bool) async {
        guard let apiKey = groqKey() else { return }
        let shouldCheck = await MainActor.run {
            GroqQuotaCheckScheduler.shouldCheck(
                hasGroqKey: true,
                secureLocalModeEnabled: secureLocalModeEnabled,
                remainingAudioSeconds: GroqQuotaStore.shared.remainingAudioSeconds,
                fallbackActive: GroqQuotaStore.shared.fallbackActive
            )
        }
        guard shouldCheck else { return }
        await checkGroqQuota(apiKey: apiKey)
    }

    private func checkGroqQuota(apiKey: String) async {
        do {
            let info = try await groqQuotaCheck(apiKey)
            if let remaining = info.remainingAudioSeconds {
                await MainActor.run {
                    GroqQuotaStore.shared.update(remainingSeconds: remaining, resetAt: info.resetAt)
                }
            }
        } catch GroqTranscriptionError.rateLimitExceeded(let resetAt) {
            await MainActor.run { GroqQuotaStore.shared.activateFallback(resetAt: resetAt) }
        } catch {
        }
    }

    @MainActor
    private func updateQuota(info: GroqRateLimitInfo, durationSeconds: TimeInterval) {
        if let remaining = info.remainingAudioSeconds {
            GroqQuotaStore.shared.update(remainingSeconds: remaining, resetAt: info.resetAt)
        }
        GroqQuotaStore.shared.recordUsage(seconds: Int(durationSeconds.rounded()))
    }

    private static func defaultOpenAITranscribe(
        audioURL: URL,
        customTerms: [String],
        language: String?
    ) async throws -> String {
        guard let apiKey = KeychainService.load(key: .openAIAPIKey) else {
            throw TranscriptionError.notConfigured
        }

        return try await Task.detached(priority: .userInitiated) {
            defer {
                try? FileManager.default.removeItem(at: audioURL)
            }

            let boundary = UUID().uuidString
            var request = URLRequest(url: transcriptionsURL)
            request.httpMethod = "POST"
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            request.setValue("text/plain, application/json", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 60
            request.cachePolicy = .reloadIgnoringLocalCacheData

            let audioData = try Data(contentsOf: audioURL, options: [.mappedIfSafe])

            let prompt = customTerms.isEmpty
                ? nil
                : "Eigennamen und Begriffe: \(customTerms.joined(separator: ", "))"
            let trimmedLanguage = language?.trimmingCharacters(in: .whitespacesAndNewlines)

            request.httpBody = MultipartFormDataBuilder.build(
                boundary: boundary,
                audioData: audioData,
                filename: "audio.m4a",
                mimeType: "audio/m4a",
                model: remoteModel,
                responseFormat: "text",
                prompt: prompt,
                language: trimmedLanguage?.isEmpty == true ? nil : trimmedLanguage
            )

            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw TranscriptionError.networkError("Ungültige Antwort")
            }

            guard httpResponse.statusCode == 200 else {
                throw TranscriptionError.apiError(openAIErrorMessage(from: data) ?? "Status \(httpResponse.statusCode)")
            }

            guard let text = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else {
                throw TranscriptionError.apiError("Transkription fehlgeschlagen")
            }

            return text
        }.value
    }

    private static func openAIErrorMessage(from data: Data) -> String? {
        (try? JSONDecoder().decode(TranscriptionOpenAIErrorResponse.self, from: data))?.error?.message
    }
}
