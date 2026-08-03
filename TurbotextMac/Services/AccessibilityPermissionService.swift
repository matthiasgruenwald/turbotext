import AppKit
import ApplicationServices

@MainActor
enum AccessibilityPermissionService {
    private static var hasPromptedThisSession = false

    static func currentStatus() -> Bool {
        AXIsProcessTrusted()
    }

    static func isTrusted(promptIfNeeded: Bool) -> Bool {
        let shouldPrompt = promptIfNeeded && !hasPromptedThisSession
        if shouldPrompt {
            hasPromptedThisSession = true
        }

        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: shouldPrompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
