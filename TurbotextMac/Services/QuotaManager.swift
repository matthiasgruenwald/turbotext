import Foundation

/// Seam over Groq quota/fallback state so routing logic doesn't depend on a concrete singleton.
/// Maps 1:1 to what ADR-0001 (persistent fallback) requires — no extra state-machine abstraction.
@MainActor
protocol QuotaManager: AnyObject {
    var fallbackActive: Bool { get }
    var rateLimitResetAt: Date? { get }
    var remainingAudioSeconds: Int? { get }
    var formattedUsedToday: String { get }

    func recordUsage(seconds: Int)
    func activateFallback(resetAt: Date?)
    func update(remainingSeconds: Int, resetAt: Date?)
    func checkIfExpired()
}
