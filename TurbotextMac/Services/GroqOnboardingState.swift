import Foundation

/// Whether the optional Groq onboarding step should be presented as open or done.
enum GroqOnboardingState: Equatable {
    case missing
    case configured

    static func resolve(hasGroqKey: Bool) -> GroqOnboardingState {
        hasGroqKey ? .configured : .missing
    }
}
