import Foundation
import Observation

/// Seam over Groq quota-usage tracking so routing logic doesn't depend on a concrete singleton.
/// Fallback activation lives in `GroqFallbackManager`, not here — this only tracks remaining
/// audio seconds and today's usage. `Observable` conformance mirrors `Workflow: AnyObject, Observable`.
@MainActor
protocol QuotaManager: AnyObject, Observable {
    var remainingAudioSeconds: Int? { get }
    var formattedUsedToday: String { get }

    func recordUsage(seconds: Int)
    func update(remainingSeconds: Int)
}
