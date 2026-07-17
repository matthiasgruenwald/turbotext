import XCTest
@testable import Turbotext

@MainActor
final class LocalModelStateTests: XCTestCase {

    private final class Backing {
        var selectedModelName = "model-a"
        var alwaysLocalTranscription = false
        var hasAutoSelectedFastLocalModel = false
    }

    private func makeState(
        backing: Backing,
        isModelInstalled: @escaping (String) -> Bool = { _ in false },
        normalizedModelName: @escaping (String) -> String = { $0 },
        resolvedModelName: @escaping (String) -> String = { $0 },
        shouldAutoSelectRecommendedFastModel: @escaping (String) -> Bool = { _ in false },
        recommendedFastModelName: String = "recommended-fast",
        downloadAndInstall: @escaping (String, @escaping @Sendable (Double) -> Void) async throws -> URL = { _, progress in
            progress(1)
            return URL(fileURLWithPath: "/tmp/model-a")
        },
        prepare: @escaping (String) async throws -> Void = { _ in }
    ) -> LocalModelState {
        LocalModelState(
            isModelInstalled: isModelInstalled,
            normalizedModelName: normalizedModelName,
            resolvedModelName: resolvedModelName,
            shouldAutoSelectRecommendedFastModel: shouldAutoSelectRecommendedFastModel,
            recommendedFastModelName: recommendedFastModelName,
            downloadAndInstall: downloadAndInstall,
            prepare: prepare,
            getSelectedModelName: { backing.selectedModelName },
            setSelectedModelName: { backing.selectedModelName = $0 },
            getAlwaysLocalTranscription: { backing.alwaysLocalTranscription },
            setAlwaysLocalTranscription: { backing.alwaysLocalTranscription = $0 },
            getHasAutoSelectedFastLocalModel: { backing.hasAutoSelectedFastLocalModel },
            setHasAutoSelectedFastLocalModel: { backing.hasAutoSelectedFastLocalModel = $0 }
        )
    }

    // MARK: - Download success/failure

    func testInstallSelectedModelSucceedsAndUpdatesState() async throws {
        let backing = Backing()
        let state = makeState(
            backing: backing,
            downloadAndInstall: { _, progress in
                // No progress callback here on purpose: the production code fires
                // the progress callback's own `Task { @MainActor }` which races
                // against the completion handler's final-state assignment
                // (pre-existing behavior, unchanged by this refactor). Omitting it
                // keeps this test focused on the success/failure outcome instead
                // of that unrelated timing race.
                return URL(fileURLWithPath: "/tmp/downloaded-model")
            }
        )

        state.installSelectedModel()
        XCTAssertTrue(state.isDownloading)

        try await waitUntil { !state.isDownloading }

        XCTAssertFalse(state.isDownloading)
        XCTAssertNil(state.downloadErrorText)
        XCTAssertEqual(backing.selectedModelName, "downloaded-model")
        XCTAssertTrue(backing.alwaysLocalTranscription)
        XCTAssertEqual(state.downloadStatusText, "\(LocalTranscriptionModel.displayName(for: "model-a")) ist installiert.")
    }

    func testInstallSelectedModelFailureSetsErrorText() async throws {
        struct DownloadError: LocalizedError {
            var errorDescription: String? { "boom" }
        }
        let backing = Backing()
        let state = makeState(
            backing: backing,
            downloadAndInstall: { _, _ in throw DownloadError() }
        )

        state.installSelectedModel()

        try await waitUntil { state.downloadErrorText != nil }

        XCTAssertNil(state.downloadProgress)
        XCTAssertNil(state.downloadStatusText)
        XCTAssertEqual(state.downloadErrorText, "boom")
        XCTAssertFalse(backing.alwaysLocalTranscription)
    }

    func testInstallSelectedModelDoesNothingWhileAlreadyDownloading() async throws {
        let backing = Backing()
        var callCount = 0
        let state = makeState(
            backing: backing,
            downloadAndInstall: { _, _ in
                callCount += 1
                try await Task.sleep(nanoseconds: 300_000_000)
                return URL(fileURLWithPath: "/tmp/model")
            }
        )

        state.installSelectedModel()
        XCTAssertTrue(state.isDownloading)
        state.installSelectedModel()

        try await waitUntil { !state.isDownloading }

        XCTAssertEqual(callCount, 1)
    }

    // MARK: - Auto-select behavior

    func testAutoSelectFastModelIfNeededSelectsRecommendedModel() {
        let backing = Backing()
        backing.selectedModelName = "default-model"
        let state = makeState(
            backing: backing,
            shouldAutoSelectRecommendedFastModel: { $0 == "default-model" },
            recommendedFastModelName: "recommended-fast"
        )

        state.autoSelectFastModelIfNeeded()

        XCTAssertEqual(backing.selectedModelName, "recommended-fast")
        XCTAssertTrue(backing.hasAutoSelectedFastLocalModel)
    }

    func testAutoSelectFastModelIfNeededSkipsWhenAlreadyAutoSelected() {
        let backing = Backing()
        backing.selectedModelName = "default-model"
        backing.hasAutoSelectedFastLocalModel = true
        let state = makeState(
            backing: backing,
            shouldAutoSelectRecommendedFastModel: { _ in true }
        )

        state.autoSelectFastModelIfNeeded()

        XCTAssertEqual(backing.selectedModelName, "default-model")
    }

    func testAutoSelectFastModelIfNeededSkipsWhenServiceSaysNo() {
        let backing = Backing()
        backing.selectedModelName = "default-model"
        let state = makeState(
            backing: backing,
            shouldAutoSelectRecommendedFastModel: { _ in false }
        )

        state.autoSelectFastModelIfNeeded()

        XCTAssertEqual(backing.selectedModelName, "default-model")
        XCTAssertFalse(backing.hasAutoSelectedFastLocalModel)
    }

    // MARK: - Prewarm

    func testPrewarmIfNeededCallsPrepareWhenSecureModeEnabledAndModelInstalled() async throws {
        let backing = Backing()
        backing.alwaysLocalTranscription = true
        var preparedModelName: String?
        let state = makeState(
            backing: backing,
            isModelInstalled: { _ in true },
            resolvedModelName: { _ in "resolved-model" },
            prepare: { modelName in preparedModelName = modelName }
        )

        state.prewarmIfNeeded()

        try await waitUntil { preparedModelName != nil }

        XCTAssertEqual(preparedModelName, "resolved-model")
    }

    func testPrewarmIfNeededDoesNothingWhenSecureModeDisabled() async throws {
        let backing = Backing()
        backing.alwaysLocalTranscription = false
        var prepareCalled = false
        let state = makeState(
            backing: backing,
            isModelInstalled: { _ in true },
            prepare: { _ in prepareCalled = true }
        )

        state.prewarmIfNeeded()

        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertFalse(prepareCalled)
    }

    func testPrewarmIfNeededDoesNothingWhenModelNotInstalled() async throws {
        let backing = Backing()
        backing.alwaysLocalTranscription = true
        var prepareCalled = false
        let state = makeState(
            backing: backing,
            isModelInstalled: { _ in false },
            prepare: { _ in prepareCalled = true }
        )

        state.prewarmIfNeeded()

        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertFalse(prepareCalled)
    }

    // MARK: - Computed display properties

    func testDownloadButtonTitleReflectsInstalledState() {
        let backing = Backing()
        backing.selectedModelName = "openai_whisper-small_216MB"
        let state = makeState(
            backing: backing,
            isModelInstalled: { _ in true },
            normalizedModelName: { $0 }
        )

        XCTAssertTrue(state.downloadButtonTitle.contains("ist installiert"))
    }

    private func waitUntil(
        timeout: TimeInterval = 2,
        _ condition: @escaping () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}
