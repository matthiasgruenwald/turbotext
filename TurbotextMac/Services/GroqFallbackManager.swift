import Foundation
import Observation

/// Owns the Groq-Fallback state machine: `idle → active(resetAt) → expired`.
/// Persists across restarts via `PersistenceProvider` (ADR-0001: fallback is
/// persistent, not session-based, so a restart during an active fallback
/// doesn't retry Groq before the quota actually resets).
@Observable
@MainActor
final class GroqFallbackManager {
    static let shared = GroqFallbackManager()

    enum State: Equatable {
        case idle
        case active(resetAt: Date?)
        case expired
    }

    private(set) var state: State

    var onStateChanged: ((Bool) -> Void)?

    private let defaults: PersistenceProvider

    private enum Keys {
        static let fallbackActive = "groqFallbackActive"
        static let resetAt = "groqRateLimitResetAt"
    }

    init(defaults: PersistenceProvider = UserDefaultsPersistence.shared) {
        self.defaults = defaults
        let wasActive = defaults.bool(forKey: Keys.fallbackActive)
        var resetAt: Date?
        if let resetInterval = defaults.object(forKey: Keys.resetAt) as? Double {
            resetAt = Date(timeIntervalSince1970: resetInterval)
        }
        if wasActive, let resetAt, Date() > resetAt {
            state = .idle
            defaults.removeObject(forKey: Keys.fallbackActive)
            defaults.removeObject(forKey: Keys.resetAt)
        } else {
            state = wasActive ? .active(resetAt: resetAt) : .idle
        }
    }

    var isActive: Bool {
        if case .active = state { return true }
        return false
    }

    var rateLimitResetAt: Date? {
        if case .active(let resetAt) = state { return resetAt }
        return nil
    }

    func reportRateLimitExceeded(resetAt: Date?) {
        state = .active(resetAt: resetAt)
        defaults.set(true, forKey: Keys.fallbackActive)
        if let resetAt {
            defaults.set(resetAt.timeIntervalSince1970, forKey: Keys.resetAt)
        }
        onStateChanged?(true)
    }

    func checkIfExpired() {
        guard case .active(let resetAt) = state, let resetAt, Date() > resetAt else { return }
        state = .expired
        defaults.removeObject(forKey: Keys.fallbackActive)
        defaults.removeObject(forKey: Keys.resetAt)
        onStateChanged?(false)
    }
}
