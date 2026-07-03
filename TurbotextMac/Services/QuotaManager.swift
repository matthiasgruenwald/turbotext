import Foundation
import Observation

/// Seam over Groq quota/fallback state so routing logic doesn't depend on a concrete singleton.
/// Maps 1:1 to what ADR-0001 (persistent fallback) requires — no extra state-machine abstraction.
/// `Observable` conformance is required so SwiftUI can track through the protocol for the
/// fallback banner — mirrors `Workflow: AnyObject, Observable`.
@MainActor
protocol QuotaManager: AnyObject, Observable {
    var fallbackActive: Bool { get }
    var rateLimitResetAt: Date? { get }
    var remainingAudioSeconds: Int? { get }
    var formattedUsedToday: String { get }
    var onFallbackChanged: ((Bool) -> Void)? { get set }

    func recordUsage(seconds: Int)
    func activateFallback(resetAt: Date?)
    func update(remainingSeconds: Int, resetAt: Date?)
    func checkIfExpired()
}
