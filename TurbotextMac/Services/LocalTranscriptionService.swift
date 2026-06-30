import Foundation
import CryptoKit
import WhisperKit

struct LocalTranscriptionModel: Identifiable, Hashable {
    let id: String
    let url: URL
    let isInstalled: Bool

    init(id: String, url: URL, isInstalled: Bool = true) {
        self.id = id
        self.url = url
        self.isInstalled = isInstalled
    }

    var displayName: String {
        Self.displayName(for: id)
    }

    var installStateLabel: String {
        isInstalled ? "Installiert" : "Nicht installiert"
    }

    var shortDisplayName: String {
        if id.contains("small") {
            return "Whisper Small"
        }
        if id.contains("base") {
            return "Whisper Base"
        }
        if id.contains("tiny") {
            return "Whisper Tiny"
        }
        if id.contains("turbo") {
            return "Whisper Turbo"
        }
        if id.contains("large-v3") {
            return "Whisper Large"
        }
        return displayName
    }

    static func displayName(for modelName: String) -> String {
        if modelName.contains("small") {
            return "Whisper Small"
        }
        if modelName.contains("base") {
            return "Whisper Base"
        }
        if modelName.contains("tiny") {
            return "Whisper Tiny"
        }
        if modelName.contains("turbo") {
            return "Whisper Large v3 Turbo"
        }
        if modelName.contains("large-v3") {
            return "Whisper Large v3"
        }
        return modelName
            .replacingOccurrences(of: "openai_", with: "")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
    }
}

enum LocalTranscriptionError: LocalizedError {
    case modelMissing(URL)
    case downloadedModelInvalid(String)
    case noText

    var errorDescription: String? {
        switch self {
        case .modelMissing(let url):
            return "Lokales Modell fehlt: \(url.path)"
        case .downloadedModelInvalid:
            return "Das geladene Modell konnte nicht verifiziert werden."
        case .noText:
            return "Das lokale Modell hat keinen Text erkannt."
        }
    }
}

struct LocalModelArtifact: Sendable {
    let size: Int
    let sha256: String
}

actor LocalTranscriptionService {
    static let shared = LocalTranscriptionService()

    static let defaultModelName = "openai_whisper-large-v3-v20240930_626MB"
    static let fastModelName = "openai_whisper-large-v3-v20240930_turbo_632MB"
    static let recommendedFastModelName = "openai_whisper-small_216MB"
    static let modelRepo = "argmaxinc/whisperkit-coreml"
    static let supportedModelNames = [
        recommendedFastModelName,
        fastModelName,
        defaultModelName
    ]
    static let supportedModelArtifacts: [String: [String: LocalModelArtifact]] = [
        "openai_whisper-large-v3-v20240930_626MB": [
            "AudioEncoder.mlmodelc/analytics/coremldata.bin": .init(size: 243, sha256: "56793886ab1adb9ca8a4e335efbe8af6640f40d958ab2d29c3ad2d7d6f712e95"),
            "AudioEncoder.mlmodelc/coremldata.bin": .init(size: 348, sha256: "ffa9eb76e8e9d9be75a4d527e5249e61d67fd43081c5aa110fd24efa6c8c5ea3"),
            "AudioEncoder.mlmodelc/metadata.json": .init(size: 1922, sha256: "a87a3375afe79e88e27af30247e234e706b98679dedfd1b021a74f7ee108c669"),
            "AudioEncoder.mlmodelc/model.mil": .init(size: 934263, sha256: "3cec2580fb07b12a88087f0e1586c6ba2982980eb36499561e1ffca2b0950442"),
            "AudioEncoder.mlmodelc/weights/weight.bin": .init(size: 421968768, sha256: "e4740fa28ed65907af754af893dfce98473fafb84dd8d718ad346985fe7678c1"),
            "MelSpectrogram.mlmodelc/analytics/coremldata.bin": .init(size: 243, sha256: "c5be419f8622083ac7046306400643539f0e7577c843448c36defc090d41e7ce"),
            "MelSpectrogram.mlmodelc/coremldata.bin": .init(size: 329, sha256: "2bfc12cffc2e45e039c7a18f384f09adffb72c182fcd93f9413d405d1a6c1130"),
            "MelSpectrogram.mlmodelc/metadata.json": .init(size: 1850, sha256: "2bc552e09a6f124d9e6c178dd1a6979e010206acb26308b2224887c9dcbeb35f"),
            "MelSpectrogram.mlmodelc/model.mil": .init(size: 10143, sha256: "c270b95b5f81d7f7d0b8a3e8f991d4e5812a37cad29349868a35b91f3a6a4463"),
            "MelSpectrogram.mlmodelc/weights/weight.bin": .init(size: 373376, sha256: "009d9fb8f6b589accfa08cebf1c712ef07c3405229ce3cfb3a57ee033c9d8a49"),
            "TextDecoder.mlmodelc/analytics/coremldata.bin": .init(size: 243, sha256: "3913b8c9716b284a917cf3744f4d415f2a05e2b910594a14c6cc10092284d3f8"),
            "TextDecoder.mlmodelc/coremldata.bin": .init(size: 633, sha256: "3faabaf66930e66956d8291d0ff485fb382496e30a91a7185548b9b898ce90a9"),
            "TextDecoder.mlmodelc/metadata.json": .init(size: 4924, sha256: "994f6030d7b1a8be999940444c3cf5d6a57d40ddd4423cf1d1fc93520aa1b052"),
            "TextDecoder.mlmodelc/model.mil": .init(size: 217177, sha256: "dbe833be9e64348c95b7fa598d0ae4309a91aedce4e82fa500a714b0e4b5d754"),
            "TextDecoder.mlmodelc/weights/weight.bin": .init(size: 203199860, sha256: "d69700903d518ada33170ab77faaaf464496fb9ff65752c6d5a6109aa2fb02db"),
            "config.json": .init(size: 1149, sha256: "f01d83dd891791d6f12421c05d3ed8ebbe70866f10d6c9a7a7e80b558ce5a0f1"),
            "generation_config.json": .init(size: 2767, sha256: "7fbb053a023be11fbeccd8421811610308143daa93d9617c52aab4a0fa1491c6")
        ],
        "openai_whisper-large-v3-v20240930_turbo_632MB": [
            "AudioEncoder.mlmodelc/analytics/coremldata.bin": .init(size: 243, sha256: "0dd9f529c744ed3c6be67f699588f7aadc4f366b5b7301dc31bd3f199944fbcc"),
            "AudioEncoder.mlmodelc/coremldata.bin": .init(size: 348, sha256: "ffa9eb76e8e9d9be75a4d527e5249e61d67fd43081c5aa110fd24efa6c8c5ea3"),
            "AudioEncoder.mlmodelc/metadata.json": .init(size: 1974, sha256: "2cd0538f90a012de3f07d38669026d527490eff1dcfd2479a81c48206a90f0a2"),
            "AudioEncoder.mlmodelc/model.mil": .init(size: 7589739, sha256: "ef5a252831e61bb91d6547fe1add3d0658895b518d47d70004322b40a2192668"),
            "AudioEncoder.mlmodelc/weights/weight.bin": .init(size: 421968768, sha256: "e4740fa28ed65907af754af893dfce98473fafb84dd8d718ad346985fe7678c1"),
            "MelSpectrogram.mlmodelc/analytics/coremldata.bin": .init(size: 243, sha256: "c5be419f8622083ac7046306400643539f0e7577c843448c36defc090d41e7ce"),
            "MelSpectrogram.mlmodelc/coremldata.bin": .init(size: 329, sha256: "98efa1e351b759e078c4044668926d32bee886caf7596ae897e08e21da45565a"),
            "MelSpectrogram.mlmodelc/metadata.json": .init(size: 1850, sha256: "2bc552e09a6f124d9e6c178dd1a6979e010206acb26308b2224887c9dcbeb35f"),
            "MelSpectrogram.mlmodelc/model.mil": .init(size: 10143, sha256: "c270b95b5f81d7f7d0b8a3e8f991d4e5812a37cad29349868a35b91f3a6a4463"),
            "MelSpectrogram.mlmodelc/weights/weight.bin": .init(size: 373376, sha256: "009d9fb8f6b589accfa08cebf1c712ef07c3405229ce3cfb3a57ee033c9d8a49"),
            "TextDecoder.mlmodelc/analytics/coremldata.bin": .init(size: 243, sha256: "4b5119bdc621c3c494f63846dc3ed43852e88826fc3b6345d42272d4b7e67724"),
            "TextDecoder.mlmodelc/coremldata.bin": .init(size: 633, sha256: "605dad4099a82cf2c7afe93e6d8e322f1c16d4160ab27bd017ec2517b81c1bdd"),
            "TextDecoder.mlmodelc/metadata.json": .init(size: 4924, sha256: "e3ce6d83884552ffcc2c34799e8e1211dcda59f1aaea5a79bf988c6cd16abbf0"),
            "TextDecoder.mlmodelc/model.mil": .init(size: 217177, sha256: "ebaf8566f367b6465276c3ed57bb99063888fa955b67828585bf19db24c85f56"),
            "TextDecoder.mlmodelc/weights/weight.bin": .init(size: 203199860, sha256: "d69700903d518ada33170ab77faaaf464496fb9ff65752c6d5a6109aa2fb02db"),
            "TextDecoderContextPrefill.mlmodelc/analytics/coremldata.bin": .init(size: 243, sha256: "97639d36c7b137ea51c3c39b175911788f4d4a601ab03cd67a4b14164c3145e1"),
            "TextDecoderContextPrefill.mlmodelc/coremldata.bin": .init(size: 380, sha256: "2c159f5c862ec187092ea58e755d8c0b298952e22f3d75da023d7693c1c7389e"),
            "TextDecoderContextPrefill.mlmodelc/metadata.json": .init(size: 2240, sha256: "eb88dc350fa6748a8bc3fa5fb10958152c138752ebbbac1824d2f99b4c9fc068"),
            "TextDecoderContextPrefill.mlmodelc/model.mil": .init(size: 4092, sha256: "990ff5052fd817e28ba7c34d9d06d324c69c7c0630b6eaac9cfdf08329dbcb34"),
            "TextDecoderContextPrefill.mlmodelc/weights/weight.bin": .init(size: 12288192, sha256: "1310070082639173e9d81508c5f220692d489e85655aa6883cc1c7506da7fcfd"),
            "config.json": .init(size: 1149, sha256: "f01d83dd891791d6f12421c05d3ed8ebbe70866f10d6c9a7a7e80b558ce5a0f1"),
            "generation_config.json": .init(size: 2767, sha256: "7fbb053a023be11fbeccd8421811610308143daa93d9617c52aab4a0fa1491c6")
        ],
        "openai_whisper-small_216MB": [
            "AudioEncoder.mlmodelc/analytics/coremldata.bin": .init(size: 243, sha256: "0c33d98d0f2046b711d75041260eb53fd0ca1c3226930a779fe9082bc4763449"),
            "AudioEncoder.mlmodelc/coremldata.bin": .init(size: 347, sha256: "bb991927256c8b71c8f5df3eb652bd0d67d933d7c36da4e53a5eb15a0a635ca1"),
            "AudioEncoder.mlmodelc/metadata.json": .init(size: 1942, sha256: "cc5b8143fddf32493a28fbd9cdda8222a862912162a665f40290f94dcbf5b4b5"),
            "AudioEncoder.mlmodelc/model.mil": .init(size: 353690, sha256: "885cd28872db8a8e471ee49c1438aa0f55bb43bec1fbeb82e89096bac61d52b4"),
            "AudioEncoder.mlmodelc/model.mlmodel": .init(size: 293185, sha256: "21680c8556cfc807eb68ae78cf498b15d805b6e655350909bd6a7a0b54b2daeb"),
            "AudioEncoder.mlmodelc/weights/weight.bin": .init(size: 62057344, sha256: "dfbda1e30a5cea269ea93e2ec69d78a6c5070c0b27982690f02d23e71fecb2d6"),
            "MelSpectrogram.mlmodelc/analytics/coremldata.bin": .init(size: 243, sha256: "c4f367993f0198e9858a4d89fb054318982c91a9bb5946e29231421c2f1100b9"),
            "MelSpectrogram.mlmodelc/coremldata.bin": .init(size: 328, sha256: "806321f1034184a10b04dc50816219dec8ae9789698712050c81edecb9bb5aa7"),
            "MelSpectrogram.mlmodelc/metadata.json": .init(size: 1878, sha256: "6a95b18553edd73f018fe954d203d9c3cfa70dfa596d140c20f519ca471fe6be"),
            "MelSpectrogram.mlmodelc/model.mil": .init(size: 10134, sha256: "7877c0f519a97a7c0dc1e0e9f8ae316bd864afcb2cffa89c770184b07e7767c9"),
            "MelSpectrogram.mlmodelc/weights/weight.bin": .init(size: 354080, sha256: "801024dbc7a89c677be1f8b285de3409e35f7d1786c9c8d9d0d6842ac57a1c83"),
            "TextDecoder.mlmodelc/analytics/coremldata.bin": .init(size: 243, sha256: "7883317b9bd8a263bd395091bfd1ebbd098826dc7c75569dcaa870691ab46554"),
            "TextDecoder.mlmodelc/coremldata.bin": .init(size: 633, sha256: "ab598c8f928071a2eee05cdc2163acea3b8d6c7d69b66b31a93dac6681c26a79"),
            "TextDecoder.mlmodelc/metadata.json": .init(size: 4935, sha256: "8bea59efa6a97b0fd5c9237a1ecb5d1c2d00b1c19970c04b2f3cef0d411cad70"),
            "TextDecoder.mlmodelc/model.mil": .init(size: 618369, sha256: "62f97fc5ba7a452d5394d48657b8c245137115a749c16680fc3b159a106d1bd2"),
            "TextDecoder.mlmodelc/model.mlmodel": .init(size: 518452, sha256: "2dac33b92f19491a71d67460384b95d56489b226f46c6074c17f3e81479bcca6"),
            "TextDecoder.mlmodelc/weights/weight.bin": .init(size: 153130482, sha256: "2be2985330071f8188e1c2ab029e1b69d6e8c42865c8d58b20b8d41856da9ed3"),
            "config.json": .init(size: 1456, sha256: "12f8d45c3e5da28148d88d257684e77296e4d922009e1bc5289b05b756859422"),
            "generation_config.json": .init(size: 2779, sha256: "169e76633bb28ac383cdfaad2527e662d0d532a15f8437ce94c02c10bc713b71")
        ]
    ]
    static let modelPageURL = URL(
        string: "https://huggingface.co/argmaxinc/whisperkit-coreml/tree/main/openai_whisper-large-v3-v20240930_626MB"
    )!
    static let fastModelPageURL = URL(
        string: "https://huggingface.co/argmaxinc/whisperkit-coreml/tree/main/openai_whisper-large-v3-v20240930_turbo_632MB"
    )!
    static let recommendedFastModelPageURL = URL(
        string: "https://huggingface.co/argmaxinc/whisperkit-coreml/tree/main/openai_whisper-small_216MB"
    )!

    static func modelPageURL(for modelName: String) -> URL {
        switch normalizedModelName(modelName) {
        case recommendedFastModelName:
            return recommendedFastModelPageURL
        case fastModelName:
            return fastModelPageURL
        case defaultModelName:
            return modelPageURL
        default:
            return URL(string: "https://huggingface.co/\(modelRepo)/tree/main/\(normalizedModelName(modelName))")!
        }
    }

    private var whisperKit: WhisperKit?
    private var loadedModelName: String?
    private let downloadModel: @Sendable (String, URL, @escaping @Sendable (Progress) -> Void) async throws -> URL
    private let expectedArtifactsByModel: [String: [String: LocalModelArtifact]]

    init(
        downloadModel: (@Sendable (String, URL, @escaping @Sendable (Progress) -> Void) async throws -> URL)? = nil,
        expectedArtifactsByModel: [String: [String: LocalModelArtifact]]? = nil
    ) {
        self.downloadModel = downloadModel ?? LocalTranscriptionService.downloadModel
        self.expectedArtifactsByModel = expectedArtifactsByModel ?? LocalTranscriptionService.supportedModelArtifacts
    }

    static var isModelInstalled: Bool {
        isModelInstalled(defaultModelName)
    }

    static func modelURL(named modelName: String) -> URL {
        AppSupportPaths.whisperKitModelsDirectoryURL.appendingPathComponent(normalizedModelName(modelName), isDirectory: true)
    }

    static func isModelInstalled(_ modelName: String) -> Bool {
        isUsableModel(at: modelURL(named: modelName))
    }

    static func normalizedModelName(_ modelName: String) -> String {
        let trimmed = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? recommendedFastModelName : trimmed
    }

    static func installedModels() -> [LocalTranscriptionModel] {
        let directory = AppSupportPaths.whisperKitModelsDirectoryURL
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return urls
            .filter { isUsableModel(at: $0) }
            .map { LocalTranscriptionModel(id: $0.lastPathComponent, url: $0) }
            .sorted { lhs, rhs in
                if lhs.id == recommendedFastModelName { return true }
                if rhs.id == recommendedFastModelName { return false }
                if lhs.id == fastModelName { return true }
                if rhs.id == fastModelName { return false }
                if lhs.id == defaultModelName { return true }
                if rhs.id == defaultModelName { return false }
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
    }

    static func modelOptions() -> [LocalTranscriptionModel] {
        var seen = Set<String>()
        let installed = installedModels()
        let installedByID = Dictionary(uniqueKeysWithValues: installed.map { ($0.id, $0) })
        let orderedIDs = supportedModelNames + installed.map(\.id)

        return orderedIDs.compactMap { modelName in
            let normalizedName = normalizedModelName(modelName)
            guard seen.insert(normalizedName).inserted else { return nil }

            if let installedModel = installedByID[normalizedName] {
                return installedModel
            }

            return LocalTranscriptionModel(
                id: normalizedName,
                url: modelURL(named: normalizedName),
                isInstalled: false
            )
        }
    }

    static func resolvedModelName(_ preferredModelName: String) -> String {
        let normalizedName = normalizedModelName(preferredModelName)
        if isModelInstalled(normalizedName) {
            return normalizedName
        }

        return installedModels().first?.id ?? normalizedName
    }

    static func shouldAutoSelectRecommendedFastModel(currentModelName: String) -> Bool {
        guard isModelInstalled(recommendedFastModelName) else {
            return false
        }

        return currentModelName == defaultModelName || currentModelName == fastModelName
    }

    func prepare(modelName: String) async throws {
        _ = try await pipeline(modelName: modelName)
    }

    func downloadAndInstall(
        modelName: String,
        progressHandler: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        let normalizedName = Self.normalizedModelName(modelName)
        let destinationURL = Self.modelURL(named: normalizedName)

        if Self.isUsableModel(at: destinationURL) {
            progressHandler(1)
            return destinationURL
        }

        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: AppSupportPaths.whisperKitModelsDirectoryURL,
            withIntermediateDirectories: true
        )

        let downloadRoot = AppSupportPaths.localModelsDirectoryURL
            .appendingPathComponent("downloads", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: downloadRoot, withIntermediateDirectories: true)

        do {
            let downloadedURL = try await downloadModel(normalizedName, downloadRoot) { progress in
                let fraction = progress.fractionCompleted
                progressHandler(fraction.isFinite ? fraction : 0)
            }

            guard Self.isExpectedDownloadedModel(
                at: downloadedURL,
                modelName: normalizedName,
                expectedArtifactsByModel: expectedArtifactsByModel
            ) else {
                throw LocalTranscriptionError.downloadedModelInvalid(normalizedName)
            }

            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.moveItem(at: downloadedURL, to: destinationURL)
            try? fileManager.removeItem(at: downloadRoot)

            if loadedModelName == normalizedName {
                whisperKit = nil
                loadedModelName = nil
            }

            progressHandler(1)
            return destinationURL
        } catch {
            try? fileManager.removeItem(at: downloadRoot)
            throw error
        }
    }

    func transcribe(audioURL: URL, language: String, modelName: String) async throws -> String {
        let resolvedLanguage = language.trimmingCharacters(in: .whitespacesAndNewlines)
        let decodeOptions = DecodingOptions(
            task: .transcribe,
            language: resolvedLanguage.isEmpty ? nil : resolvedLanguage
        )

        let pipeline = try await pipeline(modelName: modelName)
        let results = try await pipeline.transcribe(
            audioPath: audioURL.path,
            decodeOptions: decodeOptions
        )
        let text = results
            .map(\.text)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else {
            throw LocalTranscriptionError.noText
        }

        return text
    }

    private func pipeline(modelName: String) async throws -> WhisperKit {
        let resolvedModelName = Self.resolvedModelName(modelName)
        if let whisperKit, loadedModelName == resolvedModelName {
            return whisperKit
        }

        let url = Self.modelURL(named: resolvedModelName)
        guard Self.isUsableModel(at: url) else {
            throw LocalTranscriptionError.modelMissing(url)
        }

        let loaded = try await WhisperKit(
            modelFolder: url.path,
            verbose: false,
            prewarm: true,
            load: true,
            download: false
        )
        whisperKit = loaded
        loadedModelName = resolvedModelName
        return loaded
    }

    private static func isUsableModel(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.appendingPathComponent("AudioEncoder.mlmodelc").path) &&
        FileManager.default.fileExists(atPath: url.appendingPathComponent("MelSpectrogram.mlmodelc").path) &&
        FileManager.default.fileExists(atPath: url.appendingPathComponent("TextDecoder.mlmodelc").path)
    }

    private static func downloadModel(
        variant: String,
        downloadBase: URL,
        progressHandler: @escaping @Sendable (Progress) -> Void
    ) async throws -> URL {
        try await WhisperKit.download(
            variant: variant,
            downloadBase: downloadBase,
            from: modelRepo,
            progressCallback: progressHandler
        )
    }

    private static func isExpectedDownloadedModel(
        at url: URL,
        modelName: String,
        expectedArtifactsByModel: [String: [String: LocalModelArtifact]]
    ) -> Bool {
        guard let expectedArtifacts = expectedArtifactsByModel[modelName] else {
            return false
        }
        guard let actualArtifacts = actualArtifacts(at: url) else {
            return false
        }
        guard actualArtifacts.count == expectedArtifacts.count else {
            return false
        }
        for (path, artifact) in actualArtifacts {
            guard let expected = expectedArtifacts[path] else {
                return false
            }
            guard expected.size == artifact.size, expected.sha256 == artifact.sha256 else {
                return false
            }
        }
        return true
    }

    private static func actualArtifacts(at url: URL) -> [String: LocalModelArtifact]? {
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else {
            return nil
        }
        var artifacts: [String: LocalModelArtifact] = [:]
        for case let fileURL as URL in enumerator {
            guard !fileURL.hasDirectoryPath else {
                continue
            }
            guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
                  let size = values.fileSize,
                  let sha256 = sha256(for: fileURL)
            else {
                return nil
            }
            let path = fileURL.path.replacingOccurrences(of: url.path + "/", with: "")
            artifacts[path] = LocalModelArtifact(size: size, sha256: sha256)
        }
        return artifacts
    }

    private static func sha256(for fileURL: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
            return nil
        }
        var hasher = SHA256()
        while let data = try? handle.read(upToCount: 1_048_576), !data.isEmpty {
            hasher.update(data: data)
        }
        try? handle.close()
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
