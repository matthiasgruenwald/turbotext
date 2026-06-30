import XCTest
@testable import Turbotext

final class AppSupportPathsTests: XCTestCase {

    func testAppSupportDirectoryIsIsolatedFromProductionUnderTests() {
        XCTAssertFalse(AppSupportPaths.appSupportDirectoryURL.path.hasSuffix("/Turbotext"))
        XCTAssertTrue(AppSupportPaths.appSupportDirectoryURL.path.hasSuffix("/TurbotextTests"))
    }

    func testSettingsURLLivesUnderIsolatedDirectory() {
        XCTAssertEqual(
            AppSupportPaths.settingsURL,
            AppSupportPaths.appSupportDirectoryURL.appendingPathComponent("settings.json")
        )
    }

    func testDownloadAndInstallRejectsUnexpectedDownloadedModelArtifacts() async throws {
        try? FileManager.default.removeItem(at: AppSupportPaths.localModelsDirectoryURL)

        var capturedDownloadRoot: URL?
        let service = LocalTranscriptionService(
            downloadModel: { modelName, downloadRoot, _ in
                capturedDownloadRoot = downloadRoot
                let modelURL = downloadRoot.appendingPathComponent(modelName, isDirectory: true)
                try FileManager.default.createDirectory(at: modelURL, withIntermediateDirectories: true)
                try FileManager.default.createDirectory(
                    at: modelURL.appendingPathComponent("AudioEncoder.mlmodelc", isDirectory: true),
                    withIntermediateDirectories: true
                )
                try Data("tampered".utf8).write(
                    to: modelURL.appendingPathComponent("AudioEncoder.mlmodelc/coremldata.bin"),
                    options: .atomic
                )
                return modelURL
            },
            expectedArtifactsByModel: [
                LocalTranscriptionService.recommendedFastModelName: [
                    "AudioEncoder.mlmodelc/coremldata.bin": .init(size: 8, sha256: String(repeating: "0", count: 64))
                ]
            ]
        )

        await XCTAssertThrowsErrorAsync(
            try await service.downloadAndInstall(
                modelName: LocalTranscriptionService.recommendedFastModelName,
                progressHandler: { _ in }
            )
        ) { error in
            XCTAssertEqual(error.localizedDescription, "Das geladene Modell konnte nicht verifiziert werden.")
        }

        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: LocalTranscriptionService.modelURL(
                    named: LocalTranscriptionService.recommendedFastModelName
                ).path
            )
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: capturedDownloadRoot?.path ?? ""))
    }
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ errorHandler: (Error) -> Void
) async {
    do {
        _ = try await expression()
        XCTFail("Expected error to be thrown")
    } catch {
        errorHandler(error)
    }
}
