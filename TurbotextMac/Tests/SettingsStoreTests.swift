import XCTest
@testable import Turbotext

final class SettingsStoreTests: XCTestCase {
    private var fileURL: URL!

    private func encoded<T: Encodable>(_ value: T) -> Data {
        // swiftlint:disable:next force_try
        try! JSONEncoder().encode(value)
    }

    override func setUp() {
        super.setUp()
        fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SettingsStoreTests-\(UUID().uuidString).json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: fileURL)
        fileURL = nil
        super.tearDown()
    }

    func testLoadWithoutExistingFileReturnsDefaults() {
        let store = SettingsStore(fileURL: fileURL)

        let loaded = store.load()

        XCTAssertEqual(loaded.app, AppSettings())
        XCTAssertEqual(encoded(loaded.transcription), encoded(TranscriptionSettings()))
        XCTAssertEqual(encoded(loaded.textImprovement), encoded(TextImprovementSettings()))
        XCTAssertEqual(encoded(loaded.dampfAblassen), encoded(DampfAblassenSettings()))
        XCTAssertEqual(encoded(loaded.emojiText), encoded(EmojiTextSettings()))
    }

    func testSaveThenLoadRoundTripsAllSettings() {
        let store = SettingsStore(fileURL: fileURL)

        var app = AppSettings()
        app.hasSeenOnboarding = true
        app.secureLocalModeEnabled = true

        var transcription = TranscriptionSettings()
        transcription.language = "de"

        var textImprovement = TextImprovementSettings()
        textImprovement.customName = "Mein Stil"

        var dampfAblassen = DampfAblassenSettings()
        dampfAblassen.customName = "Dampf"

        var emojiText = EmojiTextSettings()
        emojiText.customName = "Emoji"

        store.save(
            app: app,
            transcription: transcription,
            textImprovement: textImprovement,
            dampfAblassen: dampfAblassen,
            emojiText: emojiText
        )

        let loaded = store.load()

        XCTAssertEqual(loaded.app, app)
        XCTAssertEqual(encoded(loaded.transcription), encoded(transcription))
        XCTAssertEqual(encoded(loaded.textImprovement), encoded(textImprovement))
        XCTAssertEqual(encoded(loaded.dampfAblassen), encoded(dampfAblassen))
        XCTAssertEqual(encoded(loaded.emojiText), encoded(emojiText))
    }

    func testSaveThenLoadRoundTripsRewritingProviderMode() {
        let store = SettingsStore(fileURL: fileURL)

        var app = AppSettings()
        app.rewritingProviderMode = .immerOpenAI

        store.save(
            app: app,
            transcription: TranscriptionSettings(),
            textImprovement: TextImprovementSettings(),
            dampfAblassen: DampfAblassenSettings(),
            emojiText: EmojiTextSettings()
        )

        let loaded = store.load()

        XCTAssertEqual(loaded.app.rewritingProviderMode, .immerOpenAI)
    }

    func testLoadWithCorruptedFileReturnsDefaults() throws {
        try "not valid json".write(to: fileURL, atomically: true, encoding: .utf8)

        let store = SettingsStore(fileURL: fileURL)
        let loaded = store.load()

        XCTAssertEqual(loaded.app, AppSettings())
    }
}
