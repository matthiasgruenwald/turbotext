import AppKit

/// Seam between `RewriteRouter` and the concrete UI/persistence for rewrite consent,
/// so `LLMService`'s local-first entry points don't need to know about `NSAlert` or
/// `AppSettings` directly. Mirrors how other services (e.g. `SettingsStore`) are
/// injected rather than reached for globally.
@MainActor
protocol RewriteConsentCoordinating {
    func presentConsent(reason: RewriteConsentReason, provider: OnlineProvider) async -> RewriteRouter.ConsentDecision
    func readConsent(_ workflow: WorkflowType) -> OnlineProvider?
    func writeConsent(_ workflow: WorkflowType, _ provider: OnlineProvider?)
}

/// Production implementation: reads/writes consent through `AppSettings.rewriteConsents`
/// (via injected closures so this stays testable without a real `SettingsState`) and
/// presents the consent choice as a native `NSAlert` — app-modal, so it's visible
/// regardless of which app currently has focus, matching the cursor-level UX for
/// hotkey-triggered background workflows that have no owning window to sheet from.
@MainActor
final class RewriteConsentCoordinator: RewriteConsentCoordinating {
    private let getConsents: () -> [WorkflowType: OnlineProvider]
    private let setConsents: ([WorkflowType: OnlineProvider]) -> Void

    init(
        getConsents: @escaping () -> [WorkflowType: OnlineProvider],
        setConsents: @escaping ([WorkflowType: OnlineProvider]) -> Void
    ) {
        self.getConsents = getConsents
        self.setConsents = setConsents
    }

    func readConsent(_ workflow: WorkflowType) -> OnlineProvider? {
        getConsents()[workflow]
    }

    func writeConsent(_ workflow: WorkflowType, _ provider: OnlineProvider?) {
        var consents = getConsents()
        consents[workflow] = provider
        setConsents(consents)
    }

    func presentConsent(reason: RewriteConsentReason, provider: OnlineProvider) async -> RewriteRouter.ConsentDecision {
        let alert = NSAlert()
        alert.messageText = "Geräteinterne Verarbeitung nicht möglich"
        alert.informativeText = reason.localizedDescription
        alert.addButton(withTitle: "Online mit \(provider.displayName) fortfahren")
        let rawTextButton = alert.addButton(withTitle: "Rohtext einfügen")
        // Escape closes the app-modal alert without a click; treat that the same as
        // explicitly choosing "Rohtext einfügen" (no dialog-affordance to just dismiss).
        rawTextButton.keyEquivalent = "\u{1b}"

        let rememberCheckbox = NSButton(checkboxWithTitle: "Für diesen Workflow merken", target: nil, action: nil)
        rememberCheckbox.state = .off
        alert.accessoryView = rememberCheckbox

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        let remember = rememberCheckbox.state == .on

        switch response {
        case .alertFirstButtonReturn:
            return .continueOnline(remember: remember)
        default:
            return .insertRawText
        }
    }
}
