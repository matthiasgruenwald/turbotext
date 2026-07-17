// PROTOTYPE — Wayfinder ticket #104. Delete after the A/B decision is recorded.

import AVFAudio
import Observation
import Speech
import SwiftUI
import WhisperKit

@main
struct AppleSpeechWhisperKitComparisonApp: App {
    var body: some Scene {
        WindowGroup("Apple Speech vs. WhisperKit — PROTOTYPE") {
            ComparisonView(model: ComparisonModel())
        }
    }
}

struct ComparisonView: View {
    @State private var model: ComparisonModel

    init(model: ComparisonModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("PROTOTYPE — keine Produktionsfunktion")
                .font(.headline)
                .foregroundStyle(.orange)
            Text("Eine Aufnahme wird nacheinander lokal mit Apple Speech und WhisperKit verarbeitet.")
            GroupBox("Messvoraussetzungen") {
                LabeledContent("Apple de-DE-Asset", value: model.appleAssetStatus)
                LabeledContent("Installierte Apple-Locales", value: model.installedLocales)
                LabeledContent("WhisperKit-Modell", value: model.modelPath)
                LabeledContent("Netzsperrtest", value: model.networkState)
            }
            HStack {
                Button(model.isRecording ? "Aufnahme beenden" : "Aufnahme starten") {
                    model.toggleRecording()
                }
                .keyboardShortcut(.defaultAction)
                Button("Anderes WhisperKit-Modell wählen") {
                    model.chooseModelDirectory()
                }
                Button("Asset-Status aktualisieren") {
                    Task { await model.refreshAppleAssetStatus() }
                }
                Button("Apple de-DE-Assets installieren") {
                    Task { await model.installAppleAssets() }
                }
                .disabled(model.isInstallingAssets || model.appleAssetStatus == "installed")
            }
            .disabled(model.isComparing)
            Text(model.status)
                .font(.callout)
            HStack(alignment: .top, spacing: 16) {
                ResultCard(title: "Apple Speech", result: model.appleResult)
                ResultCard(title: "WhisperKit", result: model.whisperResult)
            }
            GroupBox("Vollständiger Messzustand") {
                Text(model.measurementState)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
        }
        .padding(20)
        .frame(minWidth: 900, minHeight: 640)
        .task { await model.refreshAppleAssetStatus() }
    }
}

private let defaultWhisperKitModelURL = FileManager.default.urls(
    for: .applicationSupportDirectory,
    in: .userDomainMask
)
.first!
.appendingPathComponent("Turbotext/models/whisperkit/openai_whisper-small_216MB", isDirectory: true)

private struct ResultCard: View {
    let title: String
    let result: ComparisonResult

    var body: some View {
        GroupBox(title) {
            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("Laufzeit", value: result.elapsed ?? "—")
                LabeledContent("Fehler", value: result.error ?? "—")
                Text("Rohtext")
                    .font(.caption)
                Text(result.text.isEmpty ? "—" : result.text)
                    .frame(maxWidth: .infinity, minHeight: 180, alignment: .topLeading)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

@MainActor @Observable
final class ComparisonModel {
    var appleAssetStatus = "Wird geprüft"
    var installedLocales = "Wird geprüft"
    var modelPath = defaultWhisperKitModelURL.path
    var networkState = "Für den Offline-Lauf externe Netzsperre aktivieren"
    var status = "Bereit für eine Aufnahme."
    var appleResult = ComparisonResult()
    var whisperResult = ComparisonResult()
    var isRecording = false
    var isComparing = false
    var isInstallingAssets = false
    var recordingURL: URL?
    private var recorder: AVAudioRecorder?

    var measurementState: String {
        [
            "recording-url=\(recordingURL?.path ?? "none")",
            "recording=\(isRecording)",
            "comparing=\(isComparing)",
            "installing-apple-assets=\(isInstallingAssets)",
            "apple-asset=\(appleAssetStatus)",
            "apple-locales=\(installedLocales)",
            "whisper-model=\(modelPath)",
            "network=\(networkState)",
            "apple=\(appleResult.stateLine)",
            "whisper=\(whisperResult.stateLine)"
        ].joined(separator: "\n")
    }

    func refreshAppleAssetStatus() async {
        appleAssetStatus = String(describing: await appleAssetStatus())
        installedLocales = await DictationTranscriber.installedLocales
            .map(\.identifier)
            .sorted()
            .joined(separator: ", ")
    }

    func installAppleAssets() async {
        let transcriber = appleTranscriber()
        do {
            guard let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) else {
                await refreshAppleAssetStatus()
                status = "Für de-DE ist keine Asset-Installation erforderlich."
                return
            }
            isInstallingAssets = true
            status = "Apple de-DE-Assets werden installiert …"
            try await request.downloadAndInstall()
            await refreshAppleAssetStatus()
            status = "Apple de-DE-Assets sind installiert."
        } catch {
            status = "Apple-Asset-Installation fehlgeschlagen: \(error.localizedDescription)"
        }
        isInstallingAssets = false
    }

    func chooseModelDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let selectedPath = panel.url?.path {
            modelPath = selectedPath
        }
    }

    func toggleRecording() {
        if isRecording {
            recorder?.stop()
            recorder = nil
            isRecording = false
            status = "Aufnahme beendet. Starte A/B-Vergleich."
            Task { await compare() }
            return
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("turbotext-ab-comparison-\(UUID().uuidString).wav")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16
        ]
        do {
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.record()
            self.recorder = recorder
            recordingURL = url
            appleResult = ComparisonResult()
            whisperResult = ComparisonResult()
            isRecording = true
            status = "Aufnahme läuft. Zum Beenden erneut klicken."
        } catch {
            status = "Aufnahmefehler: \(error.localizedDescription)"
        }
    }

    func compare() async {
        guard let recordingURL else { return }
        let assetStatus = await appleAssetStatus()
        guard assetStatus == .installed else {
            appleResult = ComparisonResult(error: "Apple de-DE-Assets sind nicht installiert.")
            await refreshAppleAssetStatus()
            status = "Apple de-DE-Assets installieren und danach den Vergleich erneut starten."
            return
        }
        guard isUsableWhisperKitModel(at: modelPath) else {
            status = "WhisperKit-Modell unvollständig: Wähle den Modellordner, nicht tokenizer.json."
            return
        }
        isComparing = true
        status = "Apple Speech läuft …"
        appleResult = await runAppleSpeech(audioURL: recordingURL)
        status = "WhisperKit läuft …"
        whisperResult = await runWhisperKit(audioURL: recordingURL, modelPath: modelPath)
        isComparing = false
        status = "Vergleich fertig. Rohtexte und Zeiten sind nebeneinander sichtbar."
    }

    private func runAppleSpeech(audioURL: URL) async -> ComparisonResult {
        let clock = ContinuousClock()
        let started = clock.now
        do {
            let audioFile = try AVAudioFile(forReading: audioURL)
            let transcriber = appleTranscriber()
            let analyzer = SpeechAnalyzer(modules: [transcriber])
            let results = Task {
                var finalText = ""
                for try await result in transcriber.results where result.isFinal {
                    finalText = String(result.text.characters)
                }
                return finalText
            }
            try await analyzer.start(inputAudioFile: audioFile, finishAfterFile: true)
            return ComparisonResult(text: try await results.value, elapsed: String(describing: started.duration(to: clock.now)))
        } catch {
            return ComparisonResult(error: error.localizedDescription)
        }
    }

    private func runWhisperKit(audioURL: URL, modelPath: String) async -> ComparisonResult {
        let clock = ContinuousClock()
        let started = clock.now
        do {
            let whisperKit = try await WhisperKit(modelFolder: modelPath, verbose: false, prewarm: true, load: true, download: false)
            let results = try await whisperKit.transcribe(
                audioPath: audioURL.path,
                decodeOptions: DecodingOptions(task: .transcribe, language: "de")
            )
            let text = results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            return ComparisonResult(text: text, elapsed: String(describing: started.duration(to: clock.now)))
        } catch {
            return ComparisonResult(error: error.localizedDescription)
        }
    }

    private func isUsableWhisperKitModel(at path: String) -> Bool {
        let url = URL(fileURLWithPath: path, isDirectory: true)
        return ["AudioEncoder.mlmodelc", "MelSpectrogram.mlmodelc", "TextDecoder.mlmodelc"]
            .allSatisfy { FileManager.default.fileExists(atPath: url.appendingPathComponent($0).path) }
    }

    private func appleTranscriber() -> DictationTranscriber {
        DictationTranscriber(locale: Locale(identifier: "de-DE"), preset: .longDictation)
    }

    private func appleAssetStatus() async -> AssetInventory.Status {
        await AssetInventory.status(forModules: [appleTranscriber()])
    }
}

struct ComparisonResult {
    var text = ""
    var elapsed: String?
    var error: String?

    var stateLine: String {
        "elapsed=\(elapsed ?? "none") error=\(error ?? "none") text=\(text)"
    }
}
