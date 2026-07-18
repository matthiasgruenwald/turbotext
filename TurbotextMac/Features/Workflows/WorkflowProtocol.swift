import Foundation

// MARK: - Workflow State

enum WorkflowPhase: Equatable {
    case idle
    case running(String)
    case done(String)
    case error(String)

    var isActive: Bool {
        switch self {
        case .idle: return false
        default: return true
        }
    }
}

enum WorkflowLaunchSource: Equatable {
    case manual
    case hotkeyBackground

    var presentsWorkflowPage: Bool {
        switch self {
        case .manual:
            return true
        case .hotkeyBackground:
            return false
        }
    }
}

typealias WorkflowOutputHandler = @MainActor (String) -> Void
typealias WorkflowPhaseChangeHandler = @MainActor (WorkflowPhase) -> Void

/// Result of a rewrite step: the rewritten text, plus the completion label to show in
/// the signal pill (#128), e.g. "Text lokal verbessert · Apple Foundation Models".
/// `nil` when there's nothing worth reporting (e.g. raw text was inserted unmodified).
struct RewriteStepResult: Equatable {
    let text: String
    let completionLabel: String?
}

// MARK: - Workflow Protocol

@MainActor
protocol Workflow: AnyObject, Observable {
    var type: WorkflowType { get }
    var phase: WorkflowPhase { get set }
    var isRecording: Bool { get }
    var audioLevel: Float { get }
    /// Shown in the signal pill while a rewrite is processing (#128): "lokal" or "online
    /// mit ‹Anbieter›". `nil` for workflows without a rewrite step (plain transcription).
    var processingLabel: String? { get }
    /// Shown in the signal pill ~3s after the result is pasted (#128). `nil` for
    /// workflows without a rewrite step, or when nothing worth reporting happened.
    var completionLabel: String? { get }
    var onOutput: WorkflowOutputHandler? { get set }
    var onPhaseChange: WorkflowPhaseChangeHandler? { get set }

    func start()
    func stop()
    func reset()
}

extension Workflow {
    var processingLabel: String? { nil }
    var completionLabel: String? { nil }
}
