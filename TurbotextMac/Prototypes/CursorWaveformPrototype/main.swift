// PROTOTYPE — terminal shell for CursorWaveformStateMachine.swift.

import Foundation

var state = CursorWaveformState.initial

while true {
    render(state)
    guard let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
        break
    }
    if input == "q" { break }
    state = state.applying(action(for: input))
}

func action(for input: String) -> CursorWaveformAction {
    switch input {
    case "s": return .start(anchor: .insertionPoint)
    case "m": return .start(anchor: .mousePointer)
    case "f": return .startFailed(anchor: .insertionPoint, reason: "Mikrofonzugriff verweigert")
    case "l": return .receiveLevel(0.65)
    case "z": return .receiveLevel(0.02)
    case "t": return .passSecond
    case "x": return .stop
    case "o": return .processingSucceeded
    case "e": return .processingFailed(reason: "Transkription nicht verfügbar")
    case "c": return .dismissFailure
    case "r": return .retry
    default: return .receiveLevel(-1)
    }
}

func render(_ state: CursorWaveformState) {
    print("\u{001B}[2J\u{001B}[H", terminator: "")
    print("\u{001B}[1mCursornahe Live-Wellenform — PROTOTYP\u{001B}[0m")
    print()
    print("\u{001B}[1mZustand\u{001B}[0m")
    print("  Phase:          \(state.phase.rawValue)")
    print("  Anker:          \(state.anchor?.rawValue ?? "—")")
    print("  Stille:         \(state.silentSeconds) s")
    print("  Hinweiszeit:    \(state.noticeSeconds) s")
    print("  Signalverlauf:  \(bars(for: state.signalHistory))")
    print("  Fehler:         \(state.failureReason ?? "—")")
    print()
    print("\u{001B}[1mEingaben\u{001B}[0m")
    print("  [s] Start am Cursor     [m] Start am Mauszeiger     [f] Startfehler")
    print("  [l] Signal              [z] kein Signal             [t] +1 Sekunde")
    print("  [x] Aufnahme stoppen    [o] Einfügen gelingt        [e] Verarbeitung scheitert")
    print("  [c] Fehler schließen    [r] per Kürzel erneut       [q] Beenden")
    print()
    print("Eingabe: ", terminator: "")
}

func bars(for levels: [Float]) -> String {
    guard !levels.isEmpty else { return "—" }
    let glyphs = ["▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"]
    return levels.map { level in
        glyphs[min(Int(level * Float(glyphs.count)), glyphs.count - 1)]
    }.joined()
}
