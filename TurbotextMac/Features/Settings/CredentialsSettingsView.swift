import SwiftUI
import AppKit

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
