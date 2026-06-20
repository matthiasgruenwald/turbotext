import SwiftUI

enum WorkflowShortcutHint {
    static func needsInputMonitoringWarning(shortcuts: [Shortcut], inputMonitoringGranted: Bool) -> Bool {
        !inputMonitoringGranted && shortcuts.contains { $0.keyCode != nil }
    }
}

struct WorkflowShortcutListView: View {
    let type: WorkflowType
    let store: ShortcutStore
    var inputMonitoringGranted: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            let shortcuts = store.shortcuts(for: type)

            if shortcuts.isEmpty {
                Text("Kein Tastenkürzel")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(shortcuts, id: \.self) { shortcut in
                    HStack(spacing: 6) {
                        Text(shortcut.displayText)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            store.remove(shortcut, from: type)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(SubtleButtonStyle())
                    }
                }

                if WorkflowShortcutHint.needsInputMonitoringWarning(shortcuts: shortcuts, inputMonitoringGranted: inputMonitoringGranted) {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.orange)
                        Text("Benötigt Tastaturüberwachung, sonst reagiert dieses Kürzel nicht.")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            ShortcutRecorderView { shortcut in
                store.add(shortcut, for: type)
            }
        }
    }
}
