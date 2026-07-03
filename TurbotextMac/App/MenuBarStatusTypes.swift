import AppKit

enum MenuBarStatus: Equatable {
    case idle
    case recording(WorkflowType)
    case processing(WorkflowType)
    case success(WorkflowType?)
    case error(WorkflowType?)
}

/// Which cloud-mode marker the idle menu bar icon should show.
/// `.none` covers both secure-local mode and not-yet-configured states.
enum MenuBarCloudIndicator: Equatable {
    case none
    case groqReady
    case openAIFallback
}

/// Whether the menu bar icon should show a red X overlay for the current network status.
/// Only `.red` is a show-stopper; `.yellow` (degraded but working) doesn't warrant the alert.
enum MenuBarNetworkAlert {
    static func shouldShowRedX(for status: NetworkQualityStatus) -> Bool {
        status == .red
    }
}

/// Idle-state tooltip text. Missing permissions take precedence over quota info,
/// since they're the more urgent reason Turbotext might not work as expected.
enum MenuBarIdleTooltip {
    static func text(
        accessibilityGranted: Bool,
        inputMonitoringGranted: Bool,
        cloudIndicator: MenuBarCloudIndicator,
        groqQuotaUsedToday: String?
    ) -> String {
        var missing: [String] = []
        if !accessibilityGranted { missing.append("Bedienungshilfen fehlen") }
        if !inputMonitoringGranted { missing.append("Tastaturüberwachung fehlt") }

        guard missing.isEmpty else {
            return "Turbotext eingeschränkt: \(missing.joined(separator: ", "))"
        }

        guard cloudIndicator == .groqReady, let groqQuotaUsedToday else {
            return "Turbotext ist bereit"
        }
        return "Turbotext ist bereit · heute \(groqQuotaUsedToday) Groq-Kontingent genutzt"
    }
}

