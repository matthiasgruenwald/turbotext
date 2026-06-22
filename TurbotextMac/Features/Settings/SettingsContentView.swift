import SwiftUI
import AppKit

struct SettingsContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        // Every view in the tree implicitly contributes defaultValue (0) through
        // this reduce chain; overwriting would let an unrelated sibling stomp the
        // real measurement. Keep the largest value seen instead.
        value = max(value, nextValue())
    }
}

struct SettingsContentView: View {
    @Bindable var appState: AppState
    @State private var selectedSection: SettingsSection = .transcription
    @Binding var measuredContentHeight: CGFloat

    private static let sidebarWidth: CGFloat = 150
    private static let contentAreaWidth: CGFloat = 680 - sidebarWidth - 1

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebarView(selectedSection: $selectedSection)

            Divider()

            ScrollView {
                sectionView(for: selectedSection)
            }
            .frame(maxWidth: .infinity)
        }
        // Hidden, unconstrained copy purely to measure the section's natural height:
        // the visible copy above lives inside a ScrollView whose own height is driven
        // by this same measurement, so measuring it directly would be circular.
        .background(
            sectionView(for: selectedSection)
                .frame(width: Self.contentAreaWidth, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .opacity(0)
                .allowsHitTesting(false)
                .background(
                    GeometryReader { geometry in
                        Color.clear.preference(key: SettingsContentHeightKey.self, value: geometry.size.height)
                    }
                )
        )
        .onPreferenceChange(SettingsContentHeightKey.self) { measuredContentHeight = $0 }
        .onAppear {
            appState.refreshAccessibilityPermission()
            if let requestedSection = appState.requestedSettingsSection {
                selectedSection = requestedSection
                appState.requestedSettingsSection = nil
            } else {
                selectedSection = SettingsSection.defaultSection(
                    accessibilityPermissionGranted: appState.accessibilityPermissionGranted
                )
            }
        }
    }

    @ViewBuilder
    private func sectionView(for section: SettingsSection) -> some View {
        switch section {
        case .transcription:
            TranscriptionSettingsView(appState: appState)
        case .workflows:
            WorkflowsSettingsView(appState: appState)
        case .shortcuts:
            ShortcutsSettingsView(appState: appState)
        case .credentials:
            CredentialsSettingsView(appState: appState)
        case .appManagement:
            AppManagementSettingsView(appState: appState)
        }
    }
}

// MARK: - Sidebar

private struct SettingsSidebarView: View {
    @Binding var selectedSection: SettingsSection

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(SettingsSection.allCases) { section in
                Button {
                    selectedSection = section
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: section.iconName)
                            .font(.system(size: 11.5, weight: .medium))
                            .frame(width: 16)
                        Text(section.title)
                            .font(.system(size: 11.5, weight: selectedSection == section ? .semibold : .regular))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(selectedSection == section ? .primary : .secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(selectedSection == section ? Color.primary.opacity(0.06) : Color.clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(SubtleButtonStyle())
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(width: 150)
    }
}

// MARK: - Section Label (quiet style)

struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
    }
}

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
                    Image(systemName: appState.selectedLocalModelIsInstalled ? "checkmark.circle.fill" : "arrow.down.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(appState.selectedLocalModelIsInstalled ? .green : .blue)
                    Text(appState.selectedLocalModelIsInstalled ? "\(installedLocalModels.count) lokales WhisperKit-Modell installiert." : "Das ausgewählte Modell wird beim Installieren lokal gespeichert.")
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
            }

            // MARK: Mikrofon
            MicrophoneFavoritesSectionView(
                store: appState.microphoneFavoritesStore,
                availableDevices: availableDevices
            )
        }
        .padding(16)
        .onAppear {
            availableDevices = MicrophoneService.availableInputDevices()
        }
    }
}

// MARK: - 2. Workflows

struct WorkflowsSettingsView: View {
    @Bindable var appState: AppState
    @State private var newTerm = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 20) {
                turbotextPlusSection
                    .frame(maxWidth: .infinity, alignment: .leading)

                Divider()

                VStack(alignment: .leading, spacing: 16) {
                    dampfAblassenSection
                    Divider()
                    emojiTextSection
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            customTermsSection
        }
        .padding(16)
    }

    // MARK: Turbotext+
    private var turbotextPlusSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Turbotext+")

            // Tone
            VStack(alignment: .leading, spacing: 8) {
                Text("Schreibstil")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Picker("", selection: $appState.textImprovementSettings.tone) {
                    ForEach(TextImprovementSettings.TextTone.allCases) { tone in
                        Text(tone.displayName).tag(tone)
                    }
                }
                .pickerStyle(.segmented)
            }

            // System Prompt
            VStack(alignment: .leading, spacing: 8) {
                Text("Eigene Anweisung")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                AutoGrowingTextEditor(
                    text: $appState.textImprovementSettings.systemPrompt,
                    font: .system(size: 11),
                    minHeight: 64,
                    maxHeight: 220
                )
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
                    .overlay(alignment: .topLeading) {
                        if appState.textImprovementSettings.systemPrompt.isEmpty {
                            Text("z.B. \"Schreibe pr\u{00E4}gnant und ohne F\u{00FC}llw\u{00F6}rter.\"")
                                .font(.system(size: 11))
                                .foregroundStyle(.quaternary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 12)
                                .allowsHitTesting(false)
                        }
                    }
            }

            // Context
            VStack(alignment: .leading, spacing: 8) {
                Text("Kontext")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                AutoGrowingTextEditor(
                    text: $appState.textImprovementSettings.context,
                    font: .system(size: 11),
                    minHeight: 32,
                    maxHeight: 120
                )
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
                    .overlay(alignment: .topLeading) {
                        if appState.textImprovementSettings.context.isEmpty {
                            Text("z.B. \"E-Mails im Bereich Unternehmensberatung\"")
                                .font(.system(size: 11))
                                .foregroundStyle(.quaternary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 12)
                                .allowsHitTesting(false)
                        }
                    }
            }
        }
    }

    // MARK: Turbotext $%&!
    private var dampfAblassenSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Turbotext $%&!")

            VStack(alignment: .leading, spacing: 8) {
                Text("Eigene Anweisung")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                AutoGrowingTextEditor(
                    text: $appState.dampfAblassenSettings.systemPrompt,
                    font: .system(size: 11),
                    minHeight: 72,
                    maxHeight: 220
                )
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
                    .overlay(alignment: .topLeading) {
                        if appState.dampfAblassenSettings.systemPrompt.isEmpty {
                            Text("z.B. \"Formuliere den Text sachlich und freundlich um.\"")
                                .font(.system(size: 11))
                                .foregroundStyle(.quaternary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 12)
                                .allowsHitTesting(false)
                        }
                    }
            }
        }
    }

    // MARK: Turbotext :)
    private var emojiTextSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Turbotext :)")

            VStack(alignment: .leading, spacing: 8) {
                Text("Emoji-Dichte")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Picker("", selection: $appState.emojiTextSettings.emojiDensity) {
                    ForEach(EmojiTextSettings.EmojiDensity.allCases) { density in
                        Text(density.displayName).tag(density)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    // MARK: Eigennamen
    private var customTermsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Eigennamen")

            Text("Werden bei jeder Transkription berücksichtigt, egal welcher Workflow oben verwendet wird — hilft z.B. bei Namen oder Fachbegriffen, die sonst falsch verstanden werden.")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // Term chips
            if !appState.textImprovementSettings.customTerms.isEmpty {
                FlowLayout(spacing: 5) {
                    ForEach(appState.textImprovementSettings.customTerms, id: \.self) { term in
                        HStack(spacing: 3) {
                            Text(term)
                                .font(.system(size: 10.5))
                            Button {
                                withAnimation(.easeOut(duration: 0.15)) {
                                    appState.textImprovementSettings.customTerms.removeAll { $0 == term }
                                }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 7, weight: .bold))
                                    .foregroundStyle(.tertiary)
                            }
                            .buttonStyle(SubtleButtonStyle())
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color(nsColor: .controlBackgroundColor))
                        )
                        .overlay(
                            Capsule()
                                .strokeBorder(Color.primary.opacity(0.04), lineWidth: 0.5)
                        )
                    }
                }
            }

            HStack(spacing: 6) {
                TextField("Neuer Begriff", text: $newTerm)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                    .onSubmit { addTerm() }

                Button { addTerm() } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.blue.opacity(0.7))
                }
                .buttonStyle(SubtleButtonStyle())
                .disabled(newTerm.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func addTerm() {
        let trimmed = newTerm.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !appState.textImprovementSettings.customTerms.contains(trimmed) else { return }
        withAnimation(.easeOut(duration: 0.15)) {
            appState.textImprovementSettings.customTerms.append(trimmed)
        }
        newTerm = ""
    }
}

// MARK: - 3. Tastenkürzel

struct ShortcutsSettingsView: View {
    @Bindable var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: "Tastenk\u{00FC}rzel")

                // Mode picker
                VStack(alignment: .leading, spacing: 8) {
                    Text("Modus")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    Picker("", selection: $appState.appSettings.hotkeyMode) {
                        ForEach(HotkeyMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    ForEach(WorkflowType.mainMenuCases) { type in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(appState.displayName(for: type))
                                .font(.system(size: 11.5, weight: .medium))
                            WorkflowShortcutListView(
                                type: type,
                                store: appState.shortcutStore,
                                inputMonitoringGranted: appState.inputMonitoringPermissionGranted
                            )
                        }
                    }
                }
            }
        }
        .padding(16)
    }
}

// MARK: - 4. Zugangsdaten

struct CredentialsSettingsView: View {
    static let openAIAPIKeyPattern = #"^sk-[A-Za-z0-9_-]{20,}$"#
    static let groqAPIKeyPattern = #"^gsk_[A-Za-z0-9]{20,}$"#

    static func validatedKey(fromClipboardText text: String, pattern: String) -> String? {
        let firstLine = text.components(separatedBy: .newlines).first ?? text
        let trimmed = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.range(of: pattern, options: .regularExpression) != nil ? trimmed : nil
    }

    static func shouldShowCancelButton(hasExistingValue: Bool, isEditing: Bool) -> Bool {
        hasExistingValue && isEditing
    }

    static let groqKeyPageURL = URL(string: "https://console.groq.com/keys")!
    static let openAIKeyPageURL = URL(string: "https://platform.openai.com/api-keys")!

    @Bindable var appState: AppState

    private enum FieldFocus {
        case groqAPIKey
        case openAIAPIKey
    }

    @State private var groqAPIKey = ""
    @State private var editingGroqKey = false
    @State private var openAIAPIKey = ""
    @State private var editingAPIKey = false
    @State private var saved = false
    @State private var saveErrorText: String?
    @FocusState private var focusedField: FieldFocus?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            groqKeySection
            Divider()
            openAIKeySection

            if let saveErrorText {
                Text(saveErrorText)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if saved {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                    Text("Gespeichert")
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.green)
            }
        }
        .padding(16)
        .onAppear {
            load()
            if !appState.hasValue(for: .openAIAPIKey) {
                editingAPIKey = true
                focusedField = .openAIAPIKey
            }
        }
    }

    // MARK: Groq API Key
    private var groqKeySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel(text: "Groq API Key")
                Link("Key holen auf console.groq.com", destination: Self.groqKeyPageURL)
                    .font(.system(size: 10, weight: .medium))
                Spacer()
                if appState.hasValue(for: .groqAPIKey) && !editingGroqKey {
                    Button("Ändern") { editingGroqKey = true }
                        .font(.system(size: 10, weight: .medium))
                        .buttonStyle(.plain)
                        .foregroundStyle(.blue)
                }
            }

            if appState.hasValue(for: .groqAPIKey) && !editingGroqKey {
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.green.opacity(0.8))
                    Text(appState.apiKeyDisplayValue(for: .groqAPIKey))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
            } else {
                HStack(spacing: 8) {
                    SecureField("gsk_...", text: $groqAPIKey)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11.5))
                        .focused($focusedField, equals: .groqAPIKey)
                        .onSubmit { save() }

                    Button("Einfügen") {
                        pasteGroqKeyFromClipboard()
                    }
                    .buttonStyle(SubtleButtonStyle())
                }
            }

            Text("Optional. Schnellere Transkription über Groq, solange das Tages-Kontingent reicht. Danach automatisch OpenAI.")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: OpenAI API Key
    private var openAIKeySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel(text: "OpenAI API Key")
                Link("Key holen auf platform.openai.com", destination: Self.openAIKeyPageURL)
                    .font(.system(size: 10, weight: .medium))
                Spacer()
                if appState.hasValue(for: .openAIAPIKey) && !editingAPIKey {
                    Button("Ändern") { editingAPIKey = true }
                        .font(.system(size: 10, weight: .medium))
                        .buttonStyle(.plain)
                        .foregroundStyle(.blue)
                }
            }

            if appState.hasValue(for: .openAIAPIKey) && !editingAPIKey {
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.green.opacity(0.8))
                    Text(appState.apiKeyDisplayValue(for: .openAIAPIKey))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
            } else {
                HStack(spacing: 8) {
                    SecureField("sk-...", text: $openAIAPIKey)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11.5))
                        .focused($focusedField, equals: .openAIAPIKey)

                    Button("Einfügen") {
                        pasteAPIKeyFromClipboard()
                    }
                    .buttonStyle(SubtleButtonStyle())
                }
            }

            Text("Dein Key bleibt lokal in dieser App. Audio und Text werden direkt an die OpenAI API gesendet.")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func load() {
        groqAPIKey = ""
        openAIAPIKey = ""
    }

    private func save() {
        saveErrorText = nil

        // Groq key (optional)
        let trimmedGroqKey = groqAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedGroqKey.isEmpty {
            do {
                try KeychainService.save(key: .groqAPIKey, value: trimmedGroqKey)
                groqAPIKey = ""
                editingGroqKey = false
            } catch {
                saveErrorText = "Groq API Key konnte nicht gespeichert werden."
                return
            }
        }

        // OpenAI key (required)
        let trimmedAPIKey = openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if editingAPIKey || !appState.hasValue(for: .openAIAPIKey) {
            guard !trimmedAPIKey.isEmpty else {
                saveErrorText = "Bitte trage deinen OpenAI API Key ein."
                return
            }
            do {
                try KeychainService.save(key: .openAIAPIKey, value: trimmedAPIKey)
                openAIAPIKey = ""
                editingAPIKey = false
            } catch {
                saveErrorText = "OpenAI API Key konnte nicht gespeichert werden."
                return
            }
        }

        if !appState.hasValue(for: .openAIAPIKey) {
            saveErrorText = "OpenAI API Key wurde nicht persistent gespeichert. Bitte App neu starten und erneut versuchen."
            return
        }

        withAnimation(.easeInOut(duration: 0.2)) { saved = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(.easeInOut(duration: 0.2)) { saved = false }
        }
    }

    private func pasteGroqKeyFromClipboard() {
        guard let rawText = NSPasteboard.general.string(forType: .string) else {
            saveErrorText = "Zwischenablage enthält keinen Text."
            return
        }
        guard let trimmedKey = Self.validatedKey(fromClipboardText: rawText, pattern: Self.groqAPIKeyPattern) else {
            saveErrorText = "Zwischenablage enthält keinen plausiblen Groq API Key."
            return
        }
        groqAPIKey = trimmedKey
        NSPasteboard.general.clearContents()
        saveErrorText = nil
        save()
    }

    private func pasteAPIKeyFromClipboard() {
        guard let rawText = NSPasteboard.general.string(forType: .string) else {
            saveErrorText = "Zwischenablage enthält keinen Text."
            return
        }
        guard let trimmedKey = Self.validatedKey(fromClipboardText: rawText, pattern: Self.openAIAPIKeyPattern) else {
            saveErrorText = "Zwischenablage enthält keinen plausiblen OpenAI API Key."
            return
        }
        openAIAPIKey = trimmedKey
        NSPasteboard.general.clearContents()
        saveErrorText = nil
        save()
    }
}

// MARK: - 5. App-Verwaltung

struct AppManagementSettingsView: View {
    @Bindable var appState: AppState

    @State private var launchAtLoginService = LaunchAtLoginService()
    @State private var currentInstallLocation = TurbotextInstallLocationService.currentInstallLocation
    @State private var installActionErrorText: String?
    @State private var showCleanupOptions = false
    @State private var deleteLocalDataOnCleanup = true
    @State private var cleanupStatusText: String?
    @State private var cleanupErrorText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            permissionsSection

            Divider()

            inputMonitoringPermissionSection

            Divider()

            updatesSection

            Divider()

            dockModeSection

            Divider()

            launchAtLoginSection

            Divider()

            hintSection

            Divider()

            installationSection

            Divider()

            cleanupSection
        }
        .padding(16)
        .onAppear {
            launchAtLoginService.refresh()
            refreshInstallState()
        }
    }

    // MARK: Berechtigungen
    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Berechtigungen")

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: appState.accessibilityPermissionGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(appState.accessibilityPermissionGranted ? .green : .orange)
                    .frame(width: 18, height: 18)

                VStack(alignment: .leading, spacing: 3) {
                    Text(appState.accessibilityPermissionGranted ? "Direktes Einfügen ist freigegeben." : "Direktes Einfügen ist noch nicht freigegeben.")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.primary)

                    Text("Öffne Bedienungshilfen und aktiviere Turbotext. Falls Turbotext schon aktiv ist, einmal aus- und wieder einschalten.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 8) {
                Button("Bedienungshilfen öffnen") {
                    appState.requestAccessibilityPermission()
                }
                .buttonStyle(SubtleButtonStyle())

                Button("Erneut prüfen") {
                    appState.refreshAccessibilityPermission()
                }
                .buttonStyle(SubtleButtonStyle())
            }
        }
    }

    // MARK: Tastaturüberwachung
    private var inputMonitoringPermissionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Tastaturüberwachung")

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: appState.inputMonitoringPermissionGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(appState.inputMonitoringPermissionGranted ? .green : .orange)
                    .frame(width: 18, height: 18)

                VStack(alignment: .leading, spacing: 3) {
                    Text(appState.inputMonitoringPermissionGranted ? "Tastatur-Tastenkürzel sind freigegeben." : "Tastatur-Tastenkürzel (z. B. F5) sind noch nicht freigegeben.")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.primary)

                    Text("Öffne Tastaturüberwachung und aktiviere Turbotext, sonst funktionieren Tastenkürzel mit einer Taste (z. B. F5) nicht. Reine Modifikator-Kürzel (z. B. fn+⇧) sind nicht betroffen.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 8) {
                Button("Tastaturüberwachung öffnen") {
                    appState.requestInputMonitoringPermission()
                }
                .buttonStyle(SubtleButtonStyle())

                Button("Erneut prüfen") {
                    appState.refreshAccessibilityPermission()
                }
                .buttonStyle(SubtleButtonStyle())
            }

            Toggle("Warnung ausgeblendet (im Hauptfenster nicht mehr anzeigen)", isOn: $appState.appSettings.hasDismissedInputMonitoringHint)
                .toggleStyle(.checkbox)
                .font(.system(size: 10.5))
        }
    }

    // MARK: Installation
    private var installationSection: some View {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "Installation")

                Text(installationHeadline)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(installationDetail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(TurbotextInstallLocationService.bundleURL.path)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                if !TurbotextInstallLocationService.otherInstalledBundleURLs.isEmpty {
                    Text("Weitere Turbotext-Kopien auf diesem Mac können doppelte Login-Items auslösen.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 8) {
                    if TurbotextInstallLocationService.shouldOfferMoveToApplications {
                        Button("Nach /Applications bewegen") {
                            moveToApplications()
                        }
                        .buttonStyle(SubtleButtonStyle())
                    }

                    Button("Im Finder zeigen") {
                        revealInFinder(urls: [TurbotextInstallLocationService.bundleURL])
                    }
                    .buttonStyle(SubtleButtonStyle())

                    if !TurbotextInstallLocationService.otherInstalledBundleURLs.isEmpty {
                        Button("Weitere Kopien zeigen") {
                            revealInFinder(urls: TurbotextInstallLocationService.otherInstalledBundleURLs)
                        }
                        .buttonStyle(SubtleButtonStyle())
                    }
                }

                if let installActionErrorText {
                    Text(installActionErrorText)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
    }

    // MARK: Updates
    private var updatesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Updates")

            Text("Diese Preview hat keinen öffentlichen Update-Feed. Baue neue Versionen selbst aus dem Repo.")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !currentInstallLocation.isCanonicalInstall {
                Text("Hotkeys und Login-Start laufen am stabilsten, wenn Turbotext aus /Applications gestartet wird.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Updates sind in dieser Preview manuell: pull, build, starten.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Dock-Modus
    private var dockModeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Dock-Modus")

            Toggle("Dock-Icon anzeigen", isOn: $appState.appSettings.dockModeEnabled)
                .toggleStyle(.switch)

            Text(appState.appSettings.dockModeEnabled
                ? "Turbotext ist im Dock und per Cmd+Tab erreichbar."
                : "Turbotext läuft nur in der Menüleiste, kein Dock-Icon.")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Beim Anmelden
    private var launchAtLoginSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Beim Anmelden")

            Toggle("Turbotext automatisch starten", isOn: Binding(
                get: { launchAtLoginService.isEnabled },
                set: { launchAtLoginService.setEnabled($0) }
            ))
            .toggleStyle(.switch)

            Text(launchAtLoginService.errorText ?? launchAtLoginService.helperText)
                .font(.system(size: 10.5))
                .foregroundStyle(
                    launchAtLoginService.errorText == nil
                        ? AnyShapeStyle(.secondary)
                        : AnyShapeStyle(.red)
                )
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Hinweis
    private var hintSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: "Hinweis")

            Text("Für direktes Einfügen: Turbotext einmal nach /Applications legen und danach Mikrofon sowie Bedienungshilfen erlauben.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(0.03))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.primary.opacity(0.05), lineWidth: 0.5)
                )
        }
    }

    // MARK: Sauber Entfernen
    private var cleanupSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Sauber Entfernen")

            Text("Vor dem Löschen Turbotext erst auf diesem Mac bereinigen. So verschwinden Anmeldestart und lokale Daten sauber aus dem Weg.")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if showCleanupOptions {
                Toggle("Zugangsdaten und Einstellungen dieses Macs löschen", isOn: $deleteLocalDataOnCleanup)
                    .toggleStyle(.switch)

                Text("Danach Turbotext beenden und die App aus /Applications löschen. Bereits verwaiste alte Login-Items können in den Systemeinstellungen einmalig manuell entfernt werden.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Button("Abbrechen") {
                        showCleanupOptions = false
                    }
                    .buttonStyle(SubtleButtonStyle())

                    Button("Jetzt bereinigen") {
                        runCleanup()
                    }
                    .buttonStyle(SubtleButtonStyle())
                    .foregroundStyle(.red)
                }
            } else {
                Button("Entfernung vorbereiten") {
                    showCleanupOptions = true
                }
                .buttonStyle(SubtleButtonStyle())
            }

            if let cleanupStatusText {
                Text(cleanupStatusText)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.green)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let cleanupErrorText {
                Text(cleanupErrorText)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var installationHeadline: String {
        switch currentInstallLocation {
        case .applications:
            return "Turbotext liegt am richtigen Ort."
        case .userApplications:
            return "Turbotext liegt noch in ~/Applications."
        case .outsideApplications:
            return "Turbotext liegt noch nicht in /Applications."
        case .unknown:
            return "Der Installationsort konnte nicht sicher erkannt werden."
        }
    }

    private var installationDetail: String {
        switch currentInstallLocation {
        case .applications:
            if TurbotextInstallLocationService.otherInstalledBundleURLs.isEmpty {
                return "Für stabile Login-Items und Updates nur diese Kopie weiterverwenden."
            }
            return "Diese Kopie ist korrekt. Zusätzliche Kopien solltest du später entfernen."
        case .userApplications:
            return "Für stabile Hotkeys und Login-Items sollte Turbotext nur aus /Applications laufen."
        case .outsideApplications:
            return "Verschiebe Turbotext einmal nach /Applications, damit Anmeldestart und Hotkeys sauber bleiben."
        case .unknown:
            return "Öffne Turbotext möglichst direkt aus /Applications."
        }
    }

    private func refreshInstallState() {
        currentInstallLocation = TurbotextInstallLocationService.currentInstallLocation
        installActionErrorText = nil
    }

    private func moveToApplications() {
        installActionErrorText = nil

        do {
            try TurbotextInstallLocationService.moveToApplicationsAndRelaunch()
        } catch {
            installActionErrorText = error.localizedDescription
        }
    }

    private func runCleanup() {
        cleanupStatusText = nil
        cleanupErrorText = nil

        let report = deleteLocalDataOnCleanup
            ? TurbotextCleanupService.cleanupUserData()
            : TurbotextCleanupService.removeLaunchAtLoginRegistration()

        launchAtLoginService.refresh()
        refreshInstallState()

        if report.failedItems.isEmpty {
            cleanupStatusText = deleteLocalDataOnCleanup
                ? "Anmeldestart und lokale Daten wurden bereinigt. Jetzt Turbotext beenden und aus /Applications löschen."
                : "Anmeldestart wurde deaktiviert. Jetzt Turbotext beenden und aus /Applications löschen."
            showCleanupOptions = false

            let urlsToReveal = report.knownInstallBundleURLs.isEmpty
                ? [TurbotextInstallLocationService.bundleURL]
                : report.knownInstallBundleURLs
            revealInFinder(urls: urlsToReveal)
            return
        }

        let failureSummary = report.failedItems
            .map { "\($0.url.lastPathComponent): \($0.errorDescription)" }
            .joined(separator: "\n")
        cleanupErrorText = "Nicht alles konnte bereinigt werden:\n\(failureSummary)"
    }

    private func revealInFinder(urls: [URL]) {
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }
}

// MARK: - Flow Layout (for term tags)

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> (positions: [CGPoint], size: CGSize) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x)
        }

        return (positions, CGSize(width: maxX, height: y + rowHeight))
    }
}
