import Foundation
import Observation

@Observable
@MainActor
final class GroqQuotaManager: QuotaManager {
    static let shared = GroqQuotaManager()

    private(set) var remainingAudioSeconds: Int?
    private(set) var usedSecondsToday: Int

    private let defaults: PersistenceProvider

    private enum Keys {
        static let remainingSeconds = "groqRemainingAudioSeconds"
        static let usedSecondsToday = "groqUsedSecondsToday"
        static let usedDayKey = "groqUsedDayKey"
    }

    init(defaults: PersistenceProvider = UserDefaultsPersistence.shared) {
        self.defaults = defaults
        if defaults.object(forKey: Keys.remainingSeconds) != nil {
            remainingAudioSeconds = defaults.integer(forKey: Keys.remainingSeconds)
        }
        usedSecondsToday = defaults.string(forKey: Keys.usedDayKey) == Self.dayKey(for: Date())
            ? defaults.integer(forKey: Keys.usedSecondsToday)
            : 0
    }

    private static func dayKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter.string(from: date)
    }

    func recordUsage(seconds: Int) {
        recordUsage(seconds: seconds, on: Date())
    }

    func recordUsage(seconds: Int, on date: Date) {
        guard seconds > 0 else { return }
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
        defaults.removeObject(forKey: Keys.usedSecondsToday)
        defaults.removeObject(forKey: Keys.usedDayKey)
    }

    /// Test-support only: clears the persisted remaining-seconds cache so a fresh quota
    /// check runs. No production caller — resetting quota state isn't a real user flow.
    func resetRemainingAudioSeconds() {
        remainingAudioSeconds = nil
        defaults.removeObject(forKey: Keys.remainingSeconds)
    }

    func update(remainingSeconds: Int) {
        remainingAudioSeconds = remainingSeconds
        defaults.set(remainingSeconds, forKey: Keys.remainingSeconds)
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
