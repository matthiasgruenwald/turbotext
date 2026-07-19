import SwiftUI

// MARK: - Hint Banners

extension MenuBarView {
    func hintBanner(
        icon: String,
        title: String,
        detail: String,
        @ViewBuilder actions: () -> some View
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.orange)
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            actions()
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.orange.opacity(0.12), lineWidth: 0.5))
    }

    var accessibilityHintBanner: some View {
        hintBanner(
            icon: "hand.raised.fill",
            title: "Einfügen braucht Bedienungshilfen.",
            detail: "Nach Updates kann macOS die Freigabe neu verlangen."
        ) {
            Button("Öffnen") {
                appState.requestAccessibilityPermission()
            }
            .font(.system(size: 10.5, weight: .medium))
            .buttonStyle(SubtleButtonStyle())
        }
    }

    var inputMonitoringHintBanner: some View {
        hintBanner(
            icon: "keyboard.badge.exclamationmark",
            title: "Tastaturüberwachung freigeben (nur für eigene Hotkeys nötig).",
            detail: "Turbotext steht dort evtl. nicht in der Liste — über + hinzufügen."
        ) {
            Button("Öffnen") {
                appState.requestInputMonitoringPermission()
            }
            .font(.system(size: 10.5, weight: .medium))
            .buttonStyle(SubtleButtonStyle())

            Button {
                showInputMonitoringDismissConfirmation = true
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(SubtleButtonStyle())
        }
    }

    func onlineKeyHintBanner(title: String, detail: String) -> some View {
        hintBanner(icon: "key.fill", title: title, detail: detail) {
            Button("Öffnen") {
                appState.requestedSettingsSection = .credentials
                appState.page = .settings
            }
            .font(.system(size: 10.5, weight: .medium))
            .buttonStyle(SubtleButtonStyle())
        }
    }

    func groqFallbackBanner(title: String, detail: String) -> some View {
        hintBanner(icon: "exclamationmark.triangle.fill", title: title, detail: detail) {
            EmptyView()
        }
    }

    var installHintBanner: some View {
        hintBanner(
            icon: "externaldrive.badge.plus",
            title: "Für sauberen Anmeldestart nach /Applications verschieben.",
            detail: "Sonst entstehen leichter doppelte Login-Items oder uneinheitliche Updates."
        ) {
            Button("Prüfen") {
                appState.page = .settings
            }
            .font(.system(size: 10.5, weight: .medium))
            .buttonStyle(SubtleButtonStyle())
        }
    }
}
