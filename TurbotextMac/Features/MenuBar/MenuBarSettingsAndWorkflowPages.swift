import SwiftUI

// MARK: - Settings Page

extension MenuBarView {
    var settingsPage: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack {
                Button {
                    appState.page = .main
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Zur\u{00FC}ck")
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(SubtleButtonStyle())

                Spacer()

                Text("Einstellungen")
                    .font(.system(size: 12, weight: .semibold))

                Spacer()
                settingsQuickAction
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            SettingsContentView(appState: appState, measuredContentHeight: $settingsContentHeight)

            Spacer(minLength: 0)

            appFooter
        }
    }

    @ViewBuilder
    var settingsQuickAction: some View {
        if !appState.accessibilityPermissionGranted {
            Button {
                appState.requestAccessibilityPermission()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "hand.raised")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Rechte")
                        .font(.system(size: 12))
                }
                .foregroundStyle(.orange)
            }
            .buttonStyle(SubtleButtonStyle())
        } else {
            Color.clear.frame(width: 58, height: 18)
        }
    }

    // MARK: - Workflow Page

    var workflowPage: some View {
        VStack(spacing: 0) {
            if let workflow = appState.activeWorkflow {
                // Header bar
                HStack {
                    Button {
                        appState.resetCurrentWorkflow()
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 10, weight: .semibold))
                            Text("Zur\u{00FC}ck")
                                .font(.system(size: 12))
                        }
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(SubtleButtonStyle())

                    Spacer()

                    HStack(spacing: 5) {
                        Image(systemName: workflow.type.icon)
                            .font(.system(size: 11))
                            .foregroundStyle(workflowIconColor(workflow.type))
                        Text(appState.displayName(for: workflow.type))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.primary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                Divider()

                // Content
                switch workflow.type {
                case .transcription, .localTranscription:
                    if let w = workflow as? TranscriptionWorkflow {
                        TranscriptionActiveView(workflow: w)
                    }
                case .textImprover:
                    if let w = workflow as? TextImprovementWorkflow {
                        TextImproverActiveView(workflow: w)
                    }
                case .dampfAblassen:
                    if let w = workflow as? DampfAblassenWorkflow {
                        DampfAblassenActiveView(workflow: w)
                    }
                case .emojiText:
                    if let w = workflow as? EmojiTextWorkflow {
                        EmojiTextActiveView(workflow: w)
                    }
                }

                Spacer(minLength: 0)

                appFooter
            }
        }
    }

    func workflowIconColor(_ type: WorkflowType) -> Color {
        switch type {
        case .transcription: return .blue
        case .localTranscription: return .green
        case .textImprover: return .purple
        case .dampfAblassen: return .orange
        case .emojiText: return .cyan
        }
    }
}
