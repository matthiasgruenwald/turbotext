import Foundation
import Observation

@Observable
@MainActor
final class GroqQuotaStore {
    static let shared = GroqQuotaStore()

    private(set) var fallbackActive: Bool
    private(set) var remainingAudioSeconds: Int?
    private(set) var rateLimitResetAt: Date?
    private(set) var usedSecondsToday: Int

    var onFallbackChanged: ((Bool) -> Void)?

    private enum Keys {
        static let fallbackActive = "groqFallbackActive"
        static let remainingSeconds = "groqRemainingAudioSeconds"
        static let resetAt = "groqRateLimitResetAt"
        static let usedSecondsToday = "groqUsedSecondsToday"
        static let usedDayKey = "groqUsedDayKey"
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
        usedSecondsToday = defaults.string(forKey: Keys.usedDayKey) == Self.dayKey(for: Date())
            ? defaults.integer(forKey: Keys.usedSecondsToday)
            : 0
        clearIfExpired()
    }

    private static func dayKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter.string(from: date)
    }

    func recordUsage(seconds: Int, on date: Date = Date()) {
        guard seconds > 0 else { return }
        let defaults = UserDefaults.standard
        let todayKey = Self.dayKey(for: date)
        if defaults.string(forKey: Keys.usedDayKey) != todayKey {
            usedSecondsToday = 0
            defaults.set(todayKey, forKey: Keys.usedDayKey)
        }
        usedSecondsToday += seconds
        defaults.set(usedSecondsToday, forKey: Keys.usedSecondsToday)
    }

    func resetUsedToday() {
        usedSecondsToday = 0
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Keys.usedSecondsToday)
        defaults.removeObject(forKey: Keys.usedDayKey)
    }

    func clearIfExpired() {
        guard fallbackActive, let resetAt = rateLimitResetAt, Date() > resetAt else { return }
        clearFallback()
    }

    func update(remainingSeconds: Int, resetAt: Date?) {
        remainingAudioSeconds = remainingSeconds
        UserDefaults.standard.set(remainingSeconds, forKey: Keys.remainingSeconds)
        if let resetAt {
            rateLimitResetAt = resetAt
            UserDefaults.standard.set(resetAt.timeIntervalSince1970, forKey: Keys.resetAt)
        }
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
        return Self.formatSeconds(seconds)
    }

    var formattedUsedToday: String {
        Self.formatSeconds(usedSecondsToday)
    }

    private static func formatSeconds(_ seconds: Int) -> String {
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
