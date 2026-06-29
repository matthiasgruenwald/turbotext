import SwiftUI
import AppKit

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
