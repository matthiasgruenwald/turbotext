import Foundation

/// Development-only credential source that replaces the macOS Keychain.
///
/// `build.sh` signs local builds ad-hoc (`codesign --sign -`), which produces a fresh code
/// signing identity on every build. The Keychain binds each item's ACL to the identity of the
/// app that created it, so after a rebuild macOS no longer recognises Turbotext as the same app
/// and asks for the keychain password again. Simulated mode sidesteps that entirely: it never
/// calls `SecItem*`, so it can neither read nor overwrite the real keys.
final class SimulatedCredentialsStore: @unchecked Sendable {
    static let activationArgument = "--simulated-credentials"
    static let activationEnvironmentKey = "TURBOTEXT_SIMULATED_CREDENTIALS"

    private let lock = NSLock()
    private var values: [KeychainKey: String]

    init(values: [KeychainKey: String] = [:]) {
        self.values = values
    }

    func load(_ key: KeychainKey) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return values[key]
    }

    func save(_ value: String, for key: KeychainKey) {
        lock.lock()
        defer { lock.unlock() }
        values = values.merging([key: value]) { _, incoming in incoming }
    }

    func delete(_ key: KeychainKey) {
        lock.lock()
        defer { lock.unlock() }
        values = values.filter { $0.key != key }
    }

    static func environmentKey(for key: KeychainKey) -> String {
        switch key {
        case .groqAPIKey: return "TURBOTEXT_SIMULATED_GROQ_API_KEY"
        case .openAIAPIKey: return "TURBOTEXT_SIMULATED_OPENAI_API_KEY"
        }
    }

    /// Shaped to satisfy `CredentialsSettingsView`'s key patterns so every downstream check
    /// behaves as it would with a real key.
    static func defaultValue(for key: KeychainKey) -> String {
        switch key {
        case .groqAPIKey: return "gsk_simulated000000000000000000"
        case .openAIAPIKey: return "sk-simulated000000000000000000"
        }
    }

    static func isActive(arguments: [String], environment: [String: String]) -> Bool {
        if arguments.contains(activationArgument) {
            return true
        }
        return isEnabled(environment[activationEnvironmentKey])
    }

    /// An explicitly empty override means "this key is not configured", which is how a run
    /// without a Groq key — or the whole onboarding path — gets exercised.
    static func seedValues(environment: [String: String]) -> [KeychainKey: String] {
        var seeded: [KeychainKey: String] = [:]
        for key in KeychainKey.allCases {
            guard let override = environment[environmentKey(for: key)] else {
                seeded[key] = defaultValue(for: key)
                continue
            }
            let trimmed = override.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                seeded[key] = trimmed
            }
        }
        return seeded
    }

    private static func isEnabled(_ value: String?) -> Bool {
        guard let value else { return false }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "1" || normalized == "true" || normalized == "yes"
    }
}
