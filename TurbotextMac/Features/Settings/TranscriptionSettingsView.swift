import SwiftUI
import AppKit

// MARK: - 1. Transkription

struct TranscriptionSettingsView: View {
    @Bindable var appState: AppState
    @State private var availableDevices: [AudioInputDevice] = []

    private var installedLocalModels: [LocalTranscriptionModel] {
        LocalTranscriptionService.installedModels()
    }

    private var localModelOptions: [LocalTranscriptionModel] {
        LocalTranscriptionService.modelOptions()
    }

    var body: some View {
        let modeStatus = appState.transcriptionModeStatus

        VStack(alignment: .leading, spacing: 20) {

            // MARK: Lokaler Modus
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: "Sicherer Lokaler Modus")

                Toggle("Sicherer Lokaler Modus", isOn: $appState.appSettings.secureLocalModeEnabled)
                    .toggleStyle(.switch)
                    .onChange(of: appState.appSettings.secureLocalModeEnabled) { _, newValue in
                        if newValue && !appState.selectedLocalModelIsInstalled {
                            appState.installSelectedLocalModel()
                        }
                    }

                HStack(spacing: 6) {
                    Image(systemName: modeStatus.selectedLocalModelInstalled ? "checkmark.circle.fill" : "arrow.down.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(modeStatus.selectedLocalModelInstalled ? .green : .blue)
                    Text(modeStatus.localInstallStatusText(installedModelCount: installedLocalModels.count))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                HStack(spacing: 8) {
                    Text("Lokales Modell")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    Picker("", selection: Binding(
                        get: { appState.selectedLocalModelName },
                        set: { appState.appSettings.selectedLocalTranscriptionModelName = $0 }
                    )) {
                        ForEach(localModelOptions) { model in
                            Text("\(model.displayName) · \(model.installStateLabel)").tag(model.id)
                        }
                    }
                    .labelsHidden()
                    .controlSize(.small)
                    .disabled(appState.isDownloadingLocalModel)
                }

                if let progress = appState.localModelDownloadProgress {
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView(value: progress)
                        Text(appState.localModelDownloadStatusText ?? "Modell wird geladen...")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    HStack(spacing: 10) {
                        Button(appState.localModelDownloadButtonTitle) {
                            appState.installSelectedLocalModel()
                        }
                        .controlSize(.small)
                        .disabled(appState.selectedLocalModelIsInstalled)

                        Link("Modellseite", destination: LocalTranscriptionService.modelPageURL(for: appState.selectedLocalModelName))
                            .font(.system(size: 10.5, weight: .medium))
                    }
                }

                if let errorText = appState.localModelDownloadErrorText {
                    Text(errorText)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Toggle("Bei Internetausfall automatisch lokal transkribieren", isOn: $appState.appSettings.autoFallbackToLocalOnOffline)
                    .toggleStyle(.switch)
                    .disabled(!appState.selectedLocalModelIsInstalled)

                if !appState.selectedLocalModelIsInstalled {
                    Text("Erfordert ein installiertes lokales Modell.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
            }

            // MARK: Mikrofon
            MicrophoneFavoritesSectionView(
                store: appState.microphoneFavoritesStore,
                availableDevices: availableDevices
            )

            // MARK: Offline-Warnsound
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: "Offline-Warnsound")

                Text("Wenn die Internetverbindung beim Drücken eines Tastenkürzels rot angezeigt wird, spielt Turbotext diesen Sound ab. Die Aufnahme startet trotzdem normal.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Testen") {
                    OfflineWarningSoundPlayer.play(.networkUnavailable)
                }
                .buttonStyle(SubtleButtonStyle())

                Divider()

                Text("Wenn der automatische Lokal-Fallback aktiv ist, spielt Turbotext stattdessen diesen Sound: Turbotext läuft lokal weiter.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Testen") {
                    OfflineWarningSoundPlayer.play(.localFallbackActive)
                }
                .buttonStyle(SubtleButtonStyle())
            }
        }
        .padding(16)
        .onAppear {
            availableDevices = MicrophoneService.availableInputDevices()
        }
    }
}
