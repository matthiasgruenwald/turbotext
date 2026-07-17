// PROTOTYPE — visual comparison for the cursor-anchored recording indicator.

import AppKit
import SwiftUI

@main
struct CursorWaveformVisualPrototypeApp: App {
    var body: some Scene {
        WindowGroup("Cursornahe Live-Wellenform — PROTOTYP") {
            PrototypeScreen()
                .frame(minWidth: 820, minHeight: 580)
        }
        .windowResizability(.contentSize)
    }
}

private enum RecordingState: String, CaseIterable, Identifiable {
    case recording = "Aufnahme"
    case processing = "Verarbeitung"
    case silence = "Stillehinweis"
    case failure = "Startfehler"

    var id: String { rawValue }
}

private enum Variant: Int, CaseIterable, Identifiable {
    case signalPill
    case statusCard
    case transportBar

    var id: Int { rawValue }

    var name: String {
        switch self {
        case .signalPill: "A — Signal-Pille"
        case .statusCard: "B — Statuskarte"
        case .transportBar: "C — Aufnahmeleiste"
        }
    }

    var summary: String {
        switch self {
        case .signalPill: "Minimal: das Signal erklärt den Zustand."
        case .statusCard: "Explizit: Zustand und Zeit sind sofort lesbar."
        case .transportBar: "Prozesshaft: Aufnahme und Verarbeitung als Ablauf."
        }
    }
}

private struct PrototypeScreen: View {
    @State private var state = RecordingState.recording
    @State private var variant = Variant.signalPill

    var body: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(
                colors: [Color(red: 0.08, green: 0.10, blue: 0.15), Color(red: 0.15, green: 0.17, blue: 0.24)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                statePicker
                previewArea
            }
            .padding(28)

            VariantSwitcher(variant: $variant)
                .padding(.bottom, 20)
        }
        .foregroundStyle(.white)
        .onKeyPress(.leftArrow) { cycleVariant(-1); return .handled }
        .onKeyPress(.rightArrow) { cycleVariant(1); return .handled }
        .onKeyPress(characters: .init(charactersIn: "1")) { _ in variant = .signalPill; return .handled }
        .onKeyPress(characters: .init(charactersIn: "2")) { _ in variant = .statusCard; return .handled }
        .onKeyPress(characters: .init(charactersIn: "3")) { _ in variant = .transportBar; return .handled }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Cursornahe Live-Wellenform")
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                Text("VISUELLER PROTOTYP · Wegwerfcode · keine Produktionsoberfläche")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.55))
            }
            Spacer()
            Text(variant.summary)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 230, alignment: .trailing)
        }
    }

    private var statePicker: some View {
        Picker("Vorschauzustand", selection: $state) {
            ForEach(RecordingState.allCases) { state in
                Text(state.rawValue).tag(state)
            }
        }
        .pickerStyle(.segmented)
        .padding(.top, 28)
    }

    private var previewArea: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24)
                .fill(.black.opacity(0.24))
                .overlay {
                    RoundedRectangle(cornerRadius: 24)
                        .strokeBorder(.white.opacity(0.12))
                }

            VStack(spacing: 10) {
                Text("Einfügeort in der Ziel-App")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.45))
                Text("Der diktierte Text erscheint genau hier |")
                    .font(.system(size: 18, design: .serif))
                    .foregroundStyle(.white.opacity(0.78))
                indicator
                    .padding(.top, 22)
                Text(stateDescription)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.48))
                    .padding(.top, 5)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 24)
        .padding(.bottom, 62)
    }

    @ViewBuilder private var indicator: some View {
        switch variant {
        case .signalPill: SignalPill(state: state)
        case .statusCard: StatusCard(state: state)
        case .transportBar: TransportBar(state: state)
        }
    }

    private var stateDescription: String {
        switch state {
        case .recording: "Das Mikrofon liefert Signal; die Wellenform bleibt in Bewegung."
        case .processing: "Aufnahme beendet; Text wird verarbeitet."
        case .silence: "Fünf Sekunden ohne verwertbares Signal; die Aufnahme läuft weiter."
        case .failure: "Aufnahme konnte nicht starten; Meldung bleibt fünf Sekunden sichtbar."
        }
    }

    private func cycleVariant(_ direction: Int) {
        let variants = Variant.allCases
        let next = (variant.rawValue + direction + variants.count) % variants.count
        variant = variants[next]
    }
}

private struct SignalPill: View {
    let state: RecordingState

    var body: some View {
        HStack(spacing: 13) {
            stateIcon
            if state == .recording { Waveform(color: .white, showsHistory: true) }
            if state == .processing { Text("Wird verarbeitet …").font(.footnote.weight(.medium)); ProgressView().tint(.white) }
            if state == .silence { Text("Kein Mikrofonsignal erkannt").font(.footnote.weight(.medium)) }
            if state == .failure { Text("Mikrofonzugriff verweigert").font(.footnote.weight(.medium)); DismissButton() }
        }
        .padding(.horizontal, 17)
        .padding(.vertical, 8)
        .frame(width: 300, height: 40)
        .background(background)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.35), radius: 16, y: 9)
    }

    private var background: Color {
        switch state {
        case .recording, .processing: Color(red: 0.13, green: 0.15, blue: 0.20)
        case .silence: Color(red: 0.37, green: 0.27, blue: 0.06)
        case .failure: Color(red: 0.42, green: 0.10, blue: 0.12)
        }
    }

    @ViewBuilder private var stateIcon: some View {
        switch state {
        case .recording: Circle().fill(.red).frame(width: 10, height: 10)
        case .processing: Image(systemName: "sparkles").foregroundStyle(.mint)
        case .silence: Image(systemName: "mic.slash.fill").foregroundStyle(.yellow)
        case .failure: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.white)
        }
    }
}

private struct StatusCard: View {
    let state: RecordingState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(title, systemImage: symbol)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(accent)
                Spacer()
                Text(state == .failure ? "5 s" : "00:12")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.55))
                if state == .failure { DismissButton() }
            }
            Divider().overlay(.white.opacity(0.15))
            if state == .recording { Waveform(color: accent) }
            else { Text(detail).font(.caption).foregroundStyle(.white.opacity(0.82)) }
        }
        .padding(18)
        .frame(width: 300, height: 96, alignment: .topLeading)
        .background(.ultraThinMaterial.opacity(0.88))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(accent.opacity(0.7)) }
        .shadow(color: .black.opacity(0.32), radius: 18, y: 10)
    }

    private var title: String { state.rawValue }
    private var symbol: String { switch state { case .recording: "mic.fill"; case .processing: "arrow.triangle.2.circlepath"; case .silence: "waveform.slash"; case .failure: "xmark.octagon.fill" } }
    private var accent: Color { switch state { case .recording: .red; case .processing: .mint; case .silence: .yellow; case .failure: .red } }
    private var detail: String { switch state { case .recording: ""; case .processing: "Transkript wird vorbereitet …"; case .silence: "Prüfe Mikrofon und Eingangspegel."; case .failure: "Mikrofonzugriff verweigert." } }
}

private struct TransportBar: View {
    let state: RecordingState

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 0) {
                step("Aufnahme", active: state == .recording || state == .silence, done: state == .processing)
                connector
                step("Verarbeitung", active: state == .processing, done: false)
                connector
                step("Einfügen", active: false, done: false)
            }
            HStack {
                if state == .recording { Waveform(color: .cyan) }
                else { Text(message).font(.caption.weight(.medium)).foregroundStyle(accent) }
                Spacer()
                if state == .failure { DismissButton() }
            }
            .frame(height: 26)
        }
        .padding(16)
        .frame(width: 400, height: 110)
        .background(Color(red: 0.04, green: 0.06, blue: 0.09).opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(.cyan.opacity(0.32)) }
    }

    private var connector: some View { Rectangle().fill(.white.opacity(0.18)).frame(height: 1).frame(maxWidth: .infinity) }
    private func step(_ title: String, active: Bool, done: Bool) -> some View {
        VStack(spacing: 5) {
            Image(systemName: done ? "checkmark.circle.fill" : active ? "circle.inset.filled" : "circle")
                .foregroundStyle(done ? .mint : active ? accent : .white.opacity(0.32))
            Text(title).font(.caption2).foregroundStyle(active || done ? .white : .white.opacity(0.42))
        }
        .frame(width: 84)
    }
    private var accent: Color { state == .silence ? .yellow : state == .failure ? .red : .cyan }
    private var message: String { switch state { case .recording: ""; case .processing: "Audio wird transkribiert …"; case .silence: "Kein Signal seit 5 Sekunden"; case .failure: "Mikrofon konnte nicht gestartet werden" } }
}

private struct Waveform: View {
    let color: Color
    var showsHistory = false
    private let compactHeights: [CGFloat] = [5, 10, 15, 8, 18, 12, 20, 9, 16, 6, 14, 9]
    private let historyHeights: [CGFloat] = [4, 6, 10, 15, 7, 17, 10, 20, 13, 6, 16, 9, 18, 11, 5, 14, 8, 19, 12, 6, 16, 9, 20, 14, 5, 11, 18, 8, 15, 4]

    private var heights: [CGFloat] { showsHistory ? historyHeights : compactHeights }
    private var barWidth: CGFloat { showsHistory ? 4 : 3 }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(heights.indices, id: \.self) { index in
                Capsule().fill(color.opacity(index.isMultiple(of: 3) ? 1 : 0.68)).frame(width: barWidth, height: heights[index])
            }
        }
        .frame(height: 20)
    }
}

private struct DismissButton: View {
    var body: some View {
        Button(action: {}) { Image(systemName: "xmark").font(.caption.bold()).padding(6) }
            .buttonStyle(.plain)
            .background(.white.opacity(0.14))
            .clipShape(Circle())
            .accessibilityLabel("Fehler schließen")
    }
}

private struct VariantSwitcher: View {
    @Binding var variant: Variant

    var body: some View {
        HStack(spacing: 14) {
            Button { cycle(-1) } label: { Image(systemName: "chevron.left") }
            Text(variant.name).font(.subheadline.weight(.semibold)).frame(minWidth: 180)
            Button { cycle(1) } label: { Image(systemName: "chevron.right") }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.black.opacity(0.78))
        .clipShape(Capsule())
        .overlay { Capsule().strokeBorder(.white.opacity(0.25)) }
        .buttonStyle(.plain)
    }

    private func cycle(_ direction: Int) {
        let variants = Variant.allCases
        variant = variants[(variant.rawValue + direction + variants.count) % variants.count]
    }
}
