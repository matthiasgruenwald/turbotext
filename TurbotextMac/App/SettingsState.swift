import Observation

/// Owns the four persisted settings structs plus the `SettingsStore` load/save cascade.
/// `AppState` delegates all settings reads/writes here; this type does not know about
/// `AppState` directly so it can be unit-tested by injecting a `SettingsStore`.
@Observable
@MainActor
final class SettingsState {
    var appSettings: AppSettings {
        didSet {
            guard oldValue != appSettings else { return }
            save()
            onAppSettingsChanged?(oldValue, appSettings)
        }
    }
    var transcriptionSettings: TranscriptionSettings {
        didSet { save() }
    }
    var textImprovementSettings: TextImprovementSettings {
        didSet { save() }
    }
    var dampfAblassenSettings: DampfAblassenSettings {
        didSet { save() }
    }
    var emojiTextSettings: EmojiTextSettings {
        didSet { save() }
    }

    /// Fired whenever `appSettings` actually changes (old value differs from new),
    /// so the owner can react to specific field transitions without AppState itself
    /// duplicating the didSet-diffing logic.
    var onAppSettingsChanged: ((AppSettings, AppSettings) -> Void)?

    private let store: SettingsStore

    init(store: SettingsStore = SettingsStore()) {
        self.store = store
        let loaded = store.load()
        self.appSettings = loaded.app
        self.transcriptionSettings = loaded.transcription
        self.textImprovementSettings = loaded.textImprovement
        self.dampfAblassenSettings = loaded.dampfAblassen
        self.emojiTextSettings = loaded.emojiText
    }

    private func save() {
        store.save(
            app: appSettings,
            transcription: transcriptionSettings,
            textImprovement: textImprovementSettings,
            dampfAblassen: dampfAblassenSettings,
            emojiText: emojiTextSettings
        )
    }
}
