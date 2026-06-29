import SwiftUI
import AppKit

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
