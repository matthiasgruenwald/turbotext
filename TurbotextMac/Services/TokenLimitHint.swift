import Foundation

/// Pure decision logic for the "shared token budget" hint shown below the system-prompt
/// editors of workflows that route through the on-device Foundation Models provider (#127).
enum TokenLimitHint {
    static let text = "Das lokale Modell teilt sein 4096-Token-Limit zwischen System-Prompt, Rohtext und Antwort. Längere Prompts lassen weniger Platz für Diktate."

    /// Only relevant when the on-device provider is actually reachable (macOS 26+, Apple
    /// Silicon, Apple Intelligence enabled) — matches `RewriteRouter`'s own gating so the
    /// hint never appears on a device that will always fall back to an online provider.
    static var isVisible: Bool {
        RewriteRouter.resolveAppleProvider() != nil
    }
}
