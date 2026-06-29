import Foundation

/// Owns the on-disk persistence (load/save) of all app settings as a single JSON container.
///
/// `AppState` holds an instance and delegates to it; this type does not know about
/// `AppState` directly so it can be unit-tested by injecting a file URL.
struct SettingsStore {
    struct Loaded {
        var app: AppSettings
        var transcription: TranscriptionSettings
        var textImprovement: TextImprovementSettings
        var dampfAblassen: DampfAblassenSettings
        var emojiText: EmojiTextSettings
    }

    private let fileURL: URL

    init(fileURL: URL = SettingsStore.defaultFileURL) {
        self.fileURL = fileURL
    }

    private static let defaultFileURL: URL = {
        try? AppSupportPaths.ensureAppSupportDirectoryExists()
        return AppSupportPaths.settingsURL
    }()

    func load() -> Loaded {
        let container = loadContainer()
        return Loaded(
            app: container?.app ?? AppSettings(),
            transcription: container?.transcription ?? TranscriptionSettings(),
            textImprovement: container?.textImprovement ?? TextImprovementSettings(),
            dampfAblassen: container?.dampfAblassen ?? DampfAblassenSettings(),
            emojiText: container?.emojiText ?? EmojiTextSettings()
        )
    }

    func save(
        app: AppSettings,
        transcription: TranscriptionSettings,
        textImprovement: TextImprovementSettings,
        dampfAblassen: DampfAblassenSettings,
        emojiText: EmojiTextSettings
    ) {
        let container = Container(
            app: app,
            transcription: transcription,
            textImprovement: textImprovement,
            dampfAblassen: dampfAblassen,
            emojiText: emojiText
        )
        guard let data = try? JSONEncoder().encode(container) else { return }
        try? data.write(to: fileURL)
    }

    private func loadContainer() -> Container? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(Container.self, from: data)
    }

    private struct Container: Codable {
        var app: AppSettings?
        var transcription: TranscriptionSettings
        var textImprovement: TextImprovementSettings
        var dampfAblassen: DampfAblassenSettings?
        var emojiText: EmojiTextSettings?
    }
}
