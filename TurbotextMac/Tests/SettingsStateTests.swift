import XCTest
@testable import Turbotext

@MainActor
final class SettingsStateTests: XCTestCase {
    private var fileURL: URL!

    override func setUp() {
        super.setUp()
        fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SettingsStateTests-\(UUID().uuidString).json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: fileURL)
        fileURL = nil
        super.tearDown()
    }

    func testLoadsDefaultsFromStoreOnInit() {
        let state = SettingsState(store: SettingsStore(fileURL: fileURL))

        XCTAssertEqual(state.appSettings, AppSettings())
        XCTAssertEqual(state.transcriptionSettings.language, TranscriptionSettings().language)
    }

    func testMutatingAppSettingsPersistsToStore() {
        let store = SettingsStore(fileURL: fileURL)
        let state = SettingsState(store: store)

        state.appSettings.hasSeenOnboarding = true

        let reloaded = store.load()
        XCTAssertTrue(reloaded.app.hasSeenOnboarding)
    }

    func testMutatingTranscriptionSettingsPersistsToStore() {
        let store = SettingsStore(fileURL: fileURL)
        let state = SettingsState(store: store)

        state.transcriptionSettings.language = "de"

        let reloaded = store.load()
        XCTAssertEqual(reloaded.transcription.language, "de")
    }

    func testOnAppSettingsChangedFiresWithOldAndNewValueOnActualChange() {
        let state = SettingsState(store: SettingsStore(fileURL: fileURL))
        var seenOld: AppSettings?
        var seenNew: AppSettings?
        state.onAppSettingsChanged = { old, new in
            seenOld = old
            seenNew = new
        }

        state.appSettings.dockModeEnabled = false

        XCTAssertEqual(seenOld?.dockModeEnabled, true)
        XCTAssertEqual(seenNew?.dockModeEnabled, false)
    }

    func testOnAppSettingsChangedDoesNotFireWhenValueUnchanged() {
        let state = SettingsState(store: SettingsStore(fileURL: fileURL))
        var callCount = 0
        state.onAppSettingsChanged = { _, _ in callCount += 1 }

        state.appSettings = state.appSettings

        XCTAssertEqual(callCount, 0)
    }
}
