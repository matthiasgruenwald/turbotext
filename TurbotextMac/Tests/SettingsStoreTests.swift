import XCTest
@testable import Turbotext

final class SettingsStoreTests: XCTestCase {
    private var fileURL: URL!

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
        XCTAssertEqual(loaded.transcription, TranscriptionSettings())
        XCTAssertEqual(loaded.textImprovement, TextImprovementSettings())
        XCTAssertEqual(loaded.dampfAblassen, DampfAblassenSettings())
        XCTAssertEqual(loaded.emojiText, EmojiTextSettings())
    }

    func testSaveThenLoadRoundTripsAllSettings() {
        let store = SettingsStore(fileURL: fileURL)

        var app = AppSettings()
        app.hasSeenOnboarding = true
        app.alwaysLocalTranscription = true

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
        XCTAssertEqual(loaded.transcription, transcription)
        XCTAssertEqual(loaded.textImprovement, textImprovement)
        XCTAssertEqual(loaded.dampfAblassen, dampfAblassen)
        XCTAssertEqual(loaded.emojiText, emojiText)
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

    func testSaveThenLoadRoundTripsRewriteConsents() {
        let store = SettingsStore(fileURL: fileURL)

        var app = AppSettings()
        app.rewriteConsents = [.textImprover: .groq, .dampfAblassen: .openAI]

        store.save(
            app: app,
            transcription: TranscriptionSettings(),
            textImprovement: TextImprovementSettings(),
            dampfAblassen: DampfAblassenSettings(),
            emojiText: EmojiTextSettings()
        )

        let loaded = store.load()

        XCTAssertEqual(loaded.app.rewriteConsents, [.textImprover: .groq, .dampfAblassen: .openAI])
    }

    func testAppSettingsWithoutRewriteConsentsDefaultsToEmpty() throws {
        let json = "{}".data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AppSettings.self, from: json)
        XCTAssertEqual(decoded.rewriteConsents, [:])
    }

    func testLoadWithCorruptedFileReturnsDefaults() throws {
        try "not valid json".write(to: fileURL, atomically: true, encoding: .utf8)

        let store = SettingsStore(fileURL: fileURL)
        let loaded = store.load()

        XCTAssertEqual(loaded.app, AppSettings())
    }

    func testAppSettingsDecodeMigratesLegacySecureLocalModeEnabledKey() throws {
        let json = "{ \"secureLocalModeEnabled\": true }".data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AppSettings.self, from: json)
        XCTAssertTrue(decoded.alwaysLocalTranscription)
    }

    func testAppSettingsDecodePrefersNewKeyOverLegacyKey() throws {
        let json = "{ \"secureLocalModeEnabled\": true, \"alwaysLocalTranscription\": false }".data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AppSettings.self, from: json)
        XCTAssertFalse(decoded.alwaysLocalTranscription)
    }

    func testLoadMigratesLegacySecureLocalModeEnabledKeyToAlwaysLocalTranscription() throws {
        let store = SettingsStore(fileURL: fileURL)
        store.save(
            app: AppSettings(),
            transcription: TranscriptionSettings(),
            textImprovement: TextImprovementSettings(),
            dampfAblassen: DampfAblassenSettings(),
            emojiText: EmojiTextSettings()
        )

        var savedJSON = try String(contentsOf: fileURL, encoding: .utf8)
        savedJSON = savedJSON.replacingOccurrences(
            of: "\"alwaysLocalTranscription\":false",
            with: "\"secureLocalModeEnabled\":true"
        )
        try savedJSON.write(to: fileURL, atomically: true, encoding: .utf8)

        let loaded = SettingsStore(fileURL: fileURL).load()

        XCTAssertTrue(loaded.app.alwaysLocalTranscription)
    }

    func testSaveThenLoadRoundTripsLiveDictationSettings() {
        let store = SettingsStore(fileURL: fileURL)

        var transcription = TranscriptionSettings()
        transcription.liveSmoothingBackend = .online
        transcription.livePillMaxLines = 5

        store.save(
            app: AppSettings(),
            transcription: transcription,
            textImprovement: TextImprovementSettings(),
            dampfAblassen: DampfAblassenSettings(),
            emojiText: EmojiTextSettings()
        )

        let loaded = store.load()

        XCTAssertEqual(loaded.transcription.liveSmoothingBackend, .online)
        XCTAssertEqual(loaded.transcription.livePillMaxLines, 5)
    }

    func testTranscriptionSettingsDecodeWithoutLiveDictationKeysUsesDefaults() throws {
        let json = "{ \"language\": \"de\" }".data(using: .utf8)!

        let decoded = try JSONDecoder().decode(TranscriptionSettings.self, from: json)

        XCTAssertEqual(decoded.liveSmoothingBackend, .off)
        XCTAssertEqual(decoded.livePillMaxLines, 8)
    }

    func testTranscriptionSettingsMigrateLegacySmoothingEnabledToOnDevice() throws {
        let json = "{ \"liveSmoothingEnabled\": true }".data(using: .utf8)!

        let decoded = try JSONDecoder().decode(TranscriptionSettings.self, from: json)

        XCTAssertEqual(decoded.liveSmoothingBackend, .onDevice, "die Bool-Einstellung migriert auf 'Auf diesem Mac', nie still auf online")
    }

    func testTranscriptionSettingsMigrateLegacySmoothingDisabledToOff() throws {
        let json = "{ \"liveSmoothingEnabled\": false }".data(using: .utf8)!

        let decoded = try JSONDecoder().decode(TranscriptionSettings.self, from: json)

        XCTAssertEqual(decoded.liveSmoothingBackend, .off)
    }

    func testTranscriptionSettingsPreferSmoothingBackendOverLegacyKey() throws {
        let json = "{ \"liveSmoothingBackend\": \"off\", \"liveSmoothingEnabled\": true }".data(using: .utf8)!

        let decoded = try JSONDecoder().decode(TranscriptionSettings.self, from: json)

        XCTAssertEqual(decoded.liveSmoothingBackend, .off)
    }

    func testTranscriptionSettingsDecodeClampsMaxLinesIntoValidRange() throws {
        let tooHigh = "{ \"livePillMaxLines\": 99 }".data(using: .utf8)!
        let high = try JSONDecoder().decode(TranscriptionSettings.self, from: tooHigh)
        XCTAssertEqual(high.livePillMaxLines, 20)

        let tooLow = "{ \"livePillMaxLines\": 0 }".data(using: .utf8)!
        let low = try JSONDecoder().decode(TranscriptionSettings.self, from: tooLow)
        XCTAssertEqual(low.livePillMaxLines, 1)
    }
}
