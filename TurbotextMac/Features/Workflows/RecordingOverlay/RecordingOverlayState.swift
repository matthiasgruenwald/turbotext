import Foundation

enum RecordingOverlayPhase: Equatable {
    case hidden
    case recording
    case processing
}

/// Immutable snapshot of what the signal pill should show. Derived purely
/// from `MenuBarStatus` transitions plus sampled audio levels, so it can be
/// unit-tested without AppKit windows or a real workflow.
struct RecordingOverlayState: Equatable {
    static let levelHistoryLimit = 30

    let phase: RecordingOverlayPhase
    let anchor: RecordingOverlayAnchor?
    let levelHistory: [Float]

    static let hidden = RecordingOverlayState(phase: .hidden, anchor: nil, levelHistory: [])

    /// Applies one `MenuBarStatus` observation. `anchor` is only consulted when
    /// transitioning from a non-recording phase into `.recording`, so the
    /// anchor freezes at the moment recording starts and never moves after.
    func applying(menuBarStatus: MenuBarStatus, resolveAnchor: () -> RecordingOverlayAnchor) -> RecordingOverlayState {
        switch menuBarStatus {
        case .recording:
            guard phase != .recording else { return self }
            return RecordingOverlayState(phase: .recording, anchor: resolveAnchor(), levelHistory: [])
        case .processing, .success:
            guard phase == .recording || phase == .processing else { return self }
            return RecordingOverlayState(phase: .processing, anchor: anchor, levelHistory: levelHistory)
        case .idle, .error:
            return .hidden
        }
    }

    func receivingLevel(_ level: Float) -> RecordingOverlayState {
        guard phase == .recording else { return self }
        let clamped = min(max(level, 0), 1)
        let nextHistory = Array((levelHistory + [clamped]).suffix(Self.levelHistoryLimit))
        return RecordingOverlayState(phase: phase, anchor: anchor, levelHistory: nextHistory)
    }
}
