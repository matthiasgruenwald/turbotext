import SwiftUI
import AppKit

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
