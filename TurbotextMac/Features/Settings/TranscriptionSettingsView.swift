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

    private var selectedLocalBackendReady: Bool {
        switch appState.selectedLocalTranscriptionBackend {
        case .appleSpeech: return appState.isAppleSpeechAvailable
        case .whisperKit: return appState.selectedLocalModelIsInstalled
        }
    }

    var body: some View {
        let modeStatus = appState.transcriptionModeStatus

        VStack(alignment: .leading, spacing: 20) {

            // MARK: Lokaler Modus (Apple-Gerätetranskription)
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: "Lokale Transkription")

                Toggle("Immer lokal transkribieren", isOn: $appState.appSettings.alwaysLocalTranscription)
                    .toggleStyle(.switch)
                    .disabled(!selectedLocalBackendReady)
                    .onChange(of: appState.appSettings.alwaysLocalTranscription) { _, newValue in
                        if newValue {
                            appState.enableAlwaysLocalTranscription()
                        }
                    }

                if appState.selectedLocalTranscriptionBackend == .appleSpeech,
                   let hintText = AppleSpeechUnavailableHint.text(for: appState.appleSpeechAvailabilityStatus) {
                    Text(hintText)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Picker("Transkriptionssystem", selection: $appState.selectedLocalTranscriptionBackend) {
                    ForEach(LocalTranscriptionBackend.allCases) { backend in
                        Text(backend.displayName).tag(backend)
                    }
                }
                .controlSize(.small)

                if appState.selectedLocalTranscriptionBackend == .appleSpeech, appState.isInstallingAppleSpeechAssets {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Deutsche Apple-Sprachassets werden installiert …")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }
                } else if appState.selectedLocalTranscriptionBackend == .appleSpeech,
                          appState.appleSpeechAvailabilityStatus == .assetsNotInstalled {
                    Button("Deutsche Apple-Sprachassets laden") {
                        appState.installAppleSpeechAssets()
                    }
                    .controlSize(.small)
                }

                if appState.selectedLocalTranscriptionBackend == .appleSpeech,
                   let errorText = appState.appleSpeechAssetInstallationErrorText {
                    Text(errorText)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Toggle("Bei Internetausfall automatisch lokal transkribieren", isOn: $appState.appSettings.autoFallbackToLocalOnOffline)
                    .toggleStyle(.switch)
                    .disabled(!selectedLocalBackendReady)

                if !selectedLocalBackendReady {
                    Text("Erfordert das ausgewählte lokale Transkriptionssystem.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }

                Divider()

                // MARK: WhisperKit (Legacy)
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(text: "WhisperKit · Legacy")

                    HStack(spacing: 6) {
                        Image(systemName: modeStatus.selectedLocalModelInstalled ? "checkmark.circle.fill" : "arrow.down.circle.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(modeStatus.selectedLocalModelInstalled ? .green : .blue)
                        Text(modeStatus.localInstallStatusText(installedModelCount: installedLocalModels.count))
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }

                    if appState.selectedLocalTranscriptionBackend == .whisperKit {
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
                    }

                    if appState.selectedLocalTranscriptionBackend == .whisperKit, let progress = appState.localModelDownloadProgress {
                        VStack(alignment: .leading, spacing: 4) {
                            ProgressView(value: progress)
                            Text(appState.localModelDownloadStatusText ?? "Modell wird geladen...")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                        }
                    } else if appState.selectedLocalTranscriptionBackend == .whisperKit {
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
                }
            }

            if appState.selectedLocalTranscriptionBackend == .appleSpeech {
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(text: "Live-Diktat")

                    Toggle("Glättung", isOn: $appState.transcriptionSettings.liveSmoothingEnabled)
                        .toggleStyle(.switch)
                    Text("Glättet das Diktat geräteintern nach Aufnahmeende (Budget: 5 Sekunden, danach wird der Rohtext eingefügt). Kann den Abschluss verzögern; bringt derzeit vor allem bei sauberem Diktat sichtbar etwas.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Stepper(
                        "Maximale Zeilen der Pille: \(appState.transcriptionSettings.livePillMaxLines)",
                        value: $appState.transcriptionSettings.livePillMaxLines,
                        in: 1...20
                    )
                    .controlSize(.small)
                }
            }

            // MARK: Mikrofon
            MicrophoneFavoritesSectionView(
                microphoneState: appState.microphoneState,
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
