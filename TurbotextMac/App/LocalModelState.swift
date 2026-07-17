import Foundation
import Observation

/// Owns local transcription model download/prewarm/auto-select state and logic.
/// `AppState` delegates here; this type does not know about `AppState` directly so it
/// can be unit-tested by injecting `LocalTranscriptionService`-style dependencies.
@Observable
@MainActor
final class LocalModelState {
    var downloadProgress: Double?
    var downloadStatusText: String?
    var downloadErrorText: String?

    private let isModelInstalled: (String) -> Bool
    private let normalizedModelName: (String) -> String
    private let resolvedModelName: (String) -> String
    private let shouldAutoSelectRecommendedFastModel: (String) -> Bool
    private let recommendedFastModelName: String
    private let downloadAndInstall: (String, @escaping @Sendable (Double) -> Void) async throws -> URL
    private let prepare: (String) async throws -> Void

    private let getSelectedModelName: () -> String
    private let setSelectedModelName: (String) -> Void
    private let getAlwaysLocalTranscription: () -> Bool
    private let setAlwaysLocalTranscription: (Bool) -> Void
    private let getHasAutoSelectedFastLocalModel: () -> Bool
    private let setHasAutoSelectedFastLocalModel: (Bool) -> Void

    init(
        isModelInstalled: @escaping (String) -> Bool = LocalTranscriptionService.isModelInstalled,
        normalizedModelName: @escaping (String) -> String = LocalTranscriptionService.normalizedModelName,
        resolvedModelName: @escaping (String) -> String = LocalTranscriptionService.resolvedModelName,
        shouldAutoSelectRecommendedFastModel: @escaping (String) -> Bool = LocalTranscriptionService.shouldAutoSelectRecommendedFastModel,
        recommendedFastModelName: String = LocalTranscriptionService.recommendedFastModelName,
        downloadAndInstall: @escaping (String, @escaping @Sendable (Double) -> Void) async throws -> URL = { modelName, progress in
            try await LocalTranscriptionService.shared.downloadAndInstall(modelName: modelName, progressHandler: progress)
        },
        prepare: @escaping (String) async throws -> Void = { modelName in
            try await LocalTranscriptionService.shared.prepare(modelName: modelName)
        },
        getSelectedModelName: @escaping () -> String,
        setSelectedModelName: @escaping (String) -> Void,
        getAlwaysLocalTranscription: @escaping () -> Bool,
        setAlwaysLocalTranscription: @escaping (Bool) -> Void,
        getHasAutoSelectedFastLocalModel: @escaping () -> Bool,
        setHasAutoSelectedFastLocalModel: @escaping (Bool) -> Void
    ) {
        self.isModelInstalled = isModelInstalled
        self.normalizedModelName = normalizedModelName
        self.resolvedModelName = resolvedModelName
        self.shouldAutoSelectRecommendedFastModel = shouldAutoSelectRecommendedFastModel
        self.recommendedFastModelName = recommendedFastModelName
        self.downloadAndInstall = downloadAndInstall
        self.prepare = prepare
        self.getSelectedModelName = getSelectedModelName
        self.setSelectedModelName = setSelectedModelName
        self.getAlwaysLocalTranscription = getAlwaysLocalTranscription
        self.setAlwaysLocalTranscription = setAlwaysLocalTranscription
        self.getHasAutoSelectedFastLocalModel = getHasAutoSelectedFastLocalModel
        self.setHasAutoSelectedFastLocalModel = setHasAutoSelectedFastLocalModel
    }

    var resolvedLocalModelName: String {
        resolvedModelName(getSelectedModelName())
    }

    var selectedModelName: String {
        normalizedModelName(getSelectedModelName())
    }

    var selectedModelDisplayName: String {
        LocalTranscriptionModel.displayName(for: selectedModelName)
    }

    var selectedModelIsInstalled: Bool {
        isModelInstalled(selectedModelName)
    }

    var isDownloading: Bool {
        downloadProgress != nil
    }

    var downloadButtonTitle: String {
        selectedModelIsInstalled
            ? "\(LocalTranscriptionModel.displayName(for: selectedModelName)) ist installiert"
            : "\(LocalTranscriptionModel.displayName(for: selectedModelName)) installieren"
    }

    func autoSelectFastModelIfNeeded() {
        guard !getHasAutoSelectedFastLocalModel(),
              shouldAutoSelectRecommendedFastModel(getSelectedModelName()) else {
            return
        }

        setSelectedModelName(recommendedFastModelName)
        setHasAutoSelectedFastLocalModel(true)
    }

    func prewarmIfNeeded() {
        guard getAlwaysLocalTranscription(),
              isModelInstalled(resolvedLocalModelName) else {
            return
        }

        let modelName = resolvedLocalModelName
        let prepare = self.prepare
        Task.detached(priority: .utility) {
            try? await prepare(modelName)
        }
    }

    func installSelectedModel() {
        guard !isDownloading else { return }

        let modelName = selectedModelName
        downloadProgress = 0
        downloadStatusText = "Download startet..."
        downloadErrorText = nil

        Task {
            do {
                let installedURL = try await downloadAndInstall(modelName) { [weak self] progress in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        let clampedProgress = min(max(progress, 0), 1)
                        self.downloadProgress = clampedProgress
                        self.downloadStatusText = "Download \(Int(clampedProgress * 100)) %"
                    }
                }

                setSelectedModelName(installedURL.lastPathComponent)
                setAlwaysLocalTranscription(true)
                downloadProgress = nil
                downloadStatusText = "\(LocalTranscriptionModel.displayName(for: modelName)) ist installiert."
                downloadErrorText = nil

                try? await prepare(modelName)
            } catch {
                downloadProgress = nil
                downloadStatusText = nil
                downloadErrorText = error.localizedDescription
            }
        }
    }
}
