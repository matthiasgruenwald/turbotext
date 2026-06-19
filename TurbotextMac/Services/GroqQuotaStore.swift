import Foundation
import Observation

@Observable
@MainActor
final class GroqQuotaStore {
    static let shared = GroqQuotaStore()

    private(set) var fallbackActive: Bool
    private(set) var remainingAudioSeconds: Int?
    private(set) var rateLimitResetAt: Date?

    var onFallbackChanged: ((Bool) -> Void)?

    private enum Keys {
        static let fallbackActive = "groqFallbackActive"
        static let remainingSeconds = "groqRemainingAudioSeconds"
        static let resetAt = "groqRateLimitResetAt"
    }

    private init() {
        let defaults = UserDefaults.standard
        fallbackActive = defaults.bool(forKey: Keys.fallbackActive)
        if let resetInterval = defaults.object(forKey: Keys.resetAt) as? Double {
            rateLimitResetAt = Date(timeIntervalSince1970: resetInterval)
        }
        if defaults.object(forKey: Keys.remainingSeconds) != nil {
            remainingAudioSeconds = defaults.integer(forKey: Keys.remainingSeconds)
        }
        clearIfExpired()
    }

    func clearIfExpired() {
        guard fallbackActive, let resetAt = rateLimitResetAt, Date() > resetAt else { return }
        clearFallback()
    }

    func update(remainingSeconds: Int, resetAt: Date) {
        remainingAudioSeconds = remainingSeconds
        rateLimitResetAt = resetAt
        UserDefaults.standard.set(remainingSeconds, forKey: Keys.remainingSeconds)
        UserDefaults.standard.set(resetAt.timeIntervalSince1970, forKey: Keys.resetAt)
    }

    func activateFallback(resetAt: Date?) {
        fallbackActive = true
        remainingAudioSeconds = 0
        if let resetAt {
            rateLimitResetAt = resetAt
            UserDefaults.standard.set(resetAt.timeIntervalSince1970, forKey: Keys.resetAt)
        }
        UserDefaults.standard.set(true, forKey: Keys.fallbackActive)
        UserDefaults.standard.set(0, forKey: Keys.remainingSeconds)
        onFallbackChanged?(true)
    }

    private func clearFallback() {
        fallbackActive = false
        remainingAudioSeconds = nil
        rateLimitResetAt = nil
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Keys.fallbackActive)
        defaults.removeObject(forKey: Keys.remainingSeconds)
        defaults.removeObject(forKey: Keys.resetAt)
        onFallbackChanged?(false)
    }

    var formattedRemaining: String? {
        guard let seconds = remainingAudioSeconds else { return nil }
        if seconds >= 3600 {
            let h = seconds / 3600
            let m = (seconds % 3600) / 60
            return m > 0 ? "\(h) Std. \(m) Min." : "\(h) Std."
        } else if seconds >= 60 {
            return "\(seconds / 60) Min."
        } else {
            return "\(seconds) Sek."
        }
    }
}
