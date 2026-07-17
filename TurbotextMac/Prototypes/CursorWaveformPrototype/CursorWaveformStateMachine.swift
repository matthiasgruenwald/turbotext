// PROTOTYPE — throw away after the state decisions are validated.
//
// Question: Do the recording, silence, processing, insertion, and failure states
// of the cursornahen Live-Wellenform have clear, recoverable transitions?

import Foundation

enum CursorAnchor: String {
    case insertionPoint = "Einfügecursor"
    case mousePointer = "Mauszeiger (Fallback)"
}

enum CursorWaveformPhase: String {
    case idle = "Bereit"
    case recording = "Aufnahme"
    case silenceHint = "Aufnahme · Stillehinweis"
    case processing = "Verarbeitung"
    case inserted = "Eingefügt"
    case startFailure = "Aufnahmestartfehler"
    case processingFailure = "Verarbeitungsfehler"
}

enum CursorWaveformAction {
    case start(anchor: CursorAnchor)
    case startFailed(anchor: CursorAnchor, reason: String)
    case receiveLevel(Float)
    case passSecond
    case stop
    case processingSucceeded
    case processingFailed(reason: String)
    case dismissFailure
    case retry
}

struct CursorWaveformState {
    let phase: CursorWaveformPhase
    let anchor: CursorAnchor?
    let signalHistory: [Float]
    let silentSeconds: Int
    let noticeSeconds: Int
    let failureReason: String?

    static let initial = CursorWaveformState(
        phase: .idle,
        anchor: nil,
        signalHistory: [],
        silentSeconds: 0,
        noticeSeconds: 0,
        failureReason: nil
    )

    func applying(_ action: CursorWaveformAction) -> CursorWaveformState {
        switch action {
        case .start(let anchor):
            return phase == .idle || phase == .startFailure ? recording(at: anchor) : self
        case .startFailed(let anchor, let reason):
            return CursorWaveformState(
                phase: .startFailure,
                anchor: anchor,
                signalHistory: [],
                silentSeconds: 0,
                noticeSeconds: 0,
                failureReason: reason
            )
        case .receiveLevel(let level):
            return receiving(level: level)
        case .passSecond:
            return passingSecond()
        case .stop:
            return stopping()
        case .processingSucceeded:
            return phase == .processing ? completed(phase: .inserted) : self
        case .processingFailed(let reason):
            guard phase == .processing else { return self }
            return CursorWaveformState(
                phase: .processingFailure,
                anchor: anchor,
                signalHistory: signalHistory,
                silentSeconds: silentSeconds,
                noticeSeconds: 0,
                failureReason: reason
            )
        case .dismissFailure:
            return isFailure ? .initial : self
        case .retry:
            return phase == .startFailure ? recording(at: anchor ?? .mousePointer) : self
        }
    }

    private var isFailure: Bool {
        phase == .startFailure || phase == .processingFailure
    }

    private func recording(at anchor: CursorAnchor) -> CursorWaveformState {
        CursorWaveformState(
            phase: .recording,
            anchor: anchor,
            signalHistory: [],
            silentSeconds: 0,
            noticeSeconds: 0,
            failureReason: nil
        )
    }

    private func receiving(level: Float) -> CursorWaveformState {
        guard phase == .recording || phase == .silenceHint else { return self }
        let clamped = min(max(level, 0), 1)
        let nextHistory = Array((signalHistory + [clamped]).suffix(12))
        let hasUsableSignal = clamped >= 0.08

        return CursorWaveformState(
            phase: hasUsableSignal ? .recording : phase,
            anchor: anchor,
            signalHistory: nextHistory,
            silentSeconds: hasUsableSignal ? 0 : silentSeconds,
            noticeSeconds: noticeSeconds,
            failureReason: nil
        )
    }

    private func passingSecond() -> CursorWaveformState {
        if phase == .inserted {
            return .initial
        }
        if phase == .startFailure {
            guard noticeSeconds < 4 else { return .initial }
            return CursorWaveformState(
                phase: phase,
                anchor: anchor,
                signalHistory: signalHistory,
                silentSeconds: silentSeconds,
                noticeSeconds: noticeSeconds + 1,
                failureReason: failureReason
            )
        }
        guard phase == .recording || phase == .silenceHint else { return self }
        let nextSilentSeconds = silentSeconds + 1
        return CursorWaveformState(
            phase: nextSilentSeconds >= 5 ? .silenceHint : phase,
            anchor: anchor,
            signalHistory: signalHistory,
            silentSeconds: nextSilentSeconds,
            noticeSeconds: noticeSeconds,
            failureReason: nil
        )
    }

    private func stopping() -> CursorWaveformState {
        guard phase == .recording || phase == .silenceHint else { return self }
        return CursorWaveformState(
            phase: .processing,
            anchor: anchor,
            signalHistory: signalHistory,
            silentSeconds: silentSeconds,
            noticeSeconds: 0,
            failureReason: nil
        )
    }

    private func completed(phase: CursorWaveformPhase) -> CursorWaveformState {
        CursorWaveformState(
            phase: phase,
            anchor: anchor,
            signalHistory: signalHistory,
            silentSeconds: silentSeconds,
            noticeSeconds: 0,
            failureReason: nil
        )
    }
}
