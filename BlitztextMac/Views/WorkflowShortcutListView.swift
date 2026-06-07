import SwiftUI

struct WorkflowShortcutListView: View {
    let type: WorkflowType
    let store: ShortcutStore

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
            }

            ShortcutRecorderView { shortcut in
                store.add(shortcut, for: type)
            }
        }
    }
}
