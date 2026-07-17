// PROTOTYPE — three mechanisms for a full-width, thin-bar, right-to-left
// scrolling waveform inside the fixed-size signal pill. Answers: which
// rendering approach keeps bars thin, fills the whole pill width, keeps
// level-based height clearly visible, and scrolls smoothly as new samples
// arrive — without the layout regressions seen in the production attempt
// (dynamic per-frame spacing recompute inside a GeometryReader/HStack).

import AppKit
import SwiftUI

@main
struct WaveformScrollPrototypeApp: App {
    var body: some Scene {
        WindowGroup("Wellenform-Scroll — PROTOTYP") {
            PrototypeScreen()
                .frame(minWidth: 720, minHeight: 420)
        }
        .windowResizability(.contentSize)
    }
}

private enum Variant: Int, CaseIterable, Identifiable {
    case fixedGrid
    case transformScroll
    case canvasDraw

    var id: Int { rawValue }

    var name: String {
        switch self {
        case .fixedGrid: "A — Feste Zellen"
        case .transformScroll: "B — Verschobener Streifen"
        case .canvasDraw: "C — Canvas-Zeichnung"
        }
    }

    var summary: String {
        switch self {
        case .fixedGrid: "Balkenzahl passend zur Breite berechnet, jedes Tick ersetzt einen Wert (Index-Verschiebung, kein echtes Scrollen)."
        case .transformScroll: "Mehr Balken als sichtbar, ganzer Streifen gleitet animiert nach links, wird am Pillenrand geclippt."
        case .canvasDraw: "Direktes Zeichnen ohne Einzelviews — ein Canvas-Aufruf pro Frame, unempfindlich gegen Layout-Eigenheiten."
        }
    }
}

/// Shared live "audio" feed: a random-walk level generator on a timer, so all
/// three variants render the same running signal for a fair comparison.
private final class LevelFeed: ObservableObject {
    @Published var history: [Float] = []
    private var current: Float = 0.15
    private var timer: Timer?

    let tickInterval: TimeInterval = 0.08
    let capacity: Int

    init(capacity: Int) {
        self.capacity = capacity
        timer = Timer.scheduledTimer(withTimeInterval: tickInterval, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func tick() {
        let step = Float.random(in: -0.22...0.28)
        current = min(1, max(0.02, current + step))
        history.append(current)
        if history.count > capacity {
            history.removeFirst(history.count - capacity)
        }
    }

    func reset() {
        current = 0.15
        history = []
    }
}

private struct PrototypeScreen: View {
    @State private var variant = Variant.fixedGrid
    // Matches production: 260pt pill, 16pt horizontal padding, 9pt dot + 12pt spacing.
    private let waveformWidth: CGFloat = 260 - 32 - 9 - 12
    @StateObject private var feed: LevelFeed

    init() {
        let width: CGFloat = 260 - 32 - 9 - 12
        // Same target cell size the fixed-grid variant uses, so history length matches.
        let cell: CGFloat = 1.5 + 1.5
        _feed = StateObject(wrappedValue: LevelFeed(capacity: max(1, Int(width / cell))))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(
                colors: [Color(red: 0.08, green: 0.10, blue: 0.15), Color(red: 0.15, green: 0.17, blue: 0.24)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 28) {
                header
                previewArea
                debugReadout
            }
            .padding(28)

            VariantSwitcher(variant: $variant, onReset: { feed.reset() })
                .padding(.bottom, 20)
        }
        .foregroundStyle(.white)
        .onKeyPress(.leftArrow) { cycleVariant(-1); return .handled }
        .onKeyPress(.rightArrow) { cycleVariant(1); return .handled }
        .onKeyPress(characters: .init(charactersIn: "1")) { _ in variant = .fixedGrid; return .handled }
        .onKeyPress(characters: .init(charactersIn: "2")) { _ in variant = .transformScroll; return .handled }
        .onKeyPress(characters: .init(charactersIn: "r")) { _ in feed.reset(); return .handled }
        .onKeyPress(characters: .init(charactersIn: "3")) { _ in variant = .canvasDraw; return .handled }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Wellenform-Scroll")
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                Text("VISUELLER PROTOTYP · Wegwerfcode · keine Produktionsoberfläche")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.55))
            }
            Spacer()
            Text(variant.summary)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 300, alignment: .trailing)
        }
    }

    private var previewArea: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24)
                .fill(.black.opacity(0.24))
                .overlay {
                    RoundedRectangle(cornerRadius: 24)
                        .strokeBorder(.white.opacity(0.12))
                }

            SignalPill(variant: variant, feed: feed, waveformWidth: waveformWidth)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
    }

    private var debugReadout: some View {
        HStack(spacing: 18) {
            Text("Verlaufslänge: \(feed.history.count)")
            Text("Letzter Pegel: \(String(format: "%.2f", feed.history.last ?? 0))")
            Text(String(format: "Pillenbreite Wellenform: %.0fpt", waveformWidth))
        }
        .font(.caption.monospaced())
        .foregroundStyle(.white.opacity(0.5))
    }

    private func cycleVariant(_ direction: Int) {
        let variants = Variant.allCases
        let next = (variant.rawValue + direction + variants.count) % variants.count
        variant = variants[next]
    }
}

private struct SignalPill: View {
    let variant: Variant
    @ObservedObject var feed: LevelFeed
    let waveformWidth: CGFloat

    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(.red).frame(width: 9, height: 9)
            waveform
                .frame(width: waveformWidth, height: 20)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(width: 260, height: 44)
        .background(Color(red: 0.13, green: 0.15, blue: 0.20))
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.35), radius: 14, y: 8)
    }

    @ViewBuilder private var waveform: some View {
        switch variant {
        case .fixedGrid: FixedGridWaveform(history: feed.history)
        case .transformScroll: TransformScrollWaveform(history: feed.history, tickInterval: feed.tickInterval)
        case .canvasDraw: CanvasWaveform(history: feed.history, capacity: feed.capacity)
        }
    }
}

/// A — bar count fixed once from the available width; each tick shifts the
/// FIFO history array, SwiftUI re-renders the same cells with new heights.
/// This is the mechanism the original (pre-regression) production code used.
private struct FixedGridWaveform: View {
    let history: [Float]
    private let barWidth: CGFloat = 1.5
    private let spacing: CGFloat = 1.5

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(Array(history.enumerated()), id: \.offset) { _, level in
                Capsule()
                    .fill(.white.opacity(0.85))
                    .frame(width: barWidth, height: barHeight(for: level))
            }
        }
    }

    private func barHeight(for level: Float) -> CGFloat {
        3 + CGFloat(level) * 17
    }
}

/// B — keeps twice the visible bar count, animates a continuous leftward
/// offset by exactly one slot per tick so bars visibly slide rather than
/// just changing height in place. Clipped to the pill's waveform window.
private struct TransformScrollWaveform: View {
    let history: [Float]
    let tickInterval: TimeInterval
    private let barWidth: CGFloat = 1.5
    private let spacing: CGFloat = 1.5
    private var slot: CGFloat { barWidth + spacing }

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(Array(history.enumerated()), id: \.offset) { _, level in
                Capsule()
                    .fill(.white.opacity(0.85))
                    .frame(width: barWidth, height: barHeight(for: level))
            }
        }
        // Right-align so the newest bar sits at the visible right edge; the
        // strip is wider than the window and slides left as history grows.
        .frame(width: CGFloat(history.count) * slot, alignment: .trailing)
        .animation(.linear(duration: tickInterval), value: history.count)
    }

    private func barHeight(for level: Float) -> CGFloat {
        3 + CGFloat(level) * 17
    }
}

/// C — no per-bar views at all; draws capsule-ish rounded rects directly
/// into a Canvas each frame. Slot width is derived from `capacity` (the
/// full-window bar count), not the current sample count, so early in a
/// recording — few samples — bars only occupy the right edge and the rest
/// of the window stays empty. Bars are right-aligned to the newest sample;
/// once the window is full, older bars fall past x=0 and are skipped,
/// which reads as clipping off the left edge.
private struct CanvasWaveform: View {
    let history: [Float]
    let capacity: Int

    var body: some View {
        Canvas { context, size in
            guard capacity > 0 else { return }
            let slot = size.width / CGFloat(capacity)
            let barWidth = max(1, slot * 0.55)
            let startX = size.width - CGFloat(history.count) * slot
            for (index, level) in history.enumerated() {
                let x = startX + CGFloat(index) * slot + (slot - barWidth) / 2
                guard x + barWidth >= 0 else { continue }
                let height = 3 + CGFloat(level) * 17
                let rect = CGRect(x: x, y: (size.height - height) / 2, width: barWidth, height: height)
                let path = Path(roundedRect: rect, cornerRadius: barWidth / 2)
                context.fill(path, with: .color(.white.opacity(0.85)))
            }
        }
        .clipped()
    }
}

private struct VariantSwitcher: View {
    @Binding var variant: Variant
    let onReset: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button { cycle(-1) } label: { Image(systemName: "chevron.left") }
            Text(variant.name).font(.subheadline.weight(.semibold)).frame(minWidth: 220)
            Button { cycle(1) } label: { Image(systemName: "chevron.right") }
            Divider().frame(height: 16)
            Button { onReset() } label: { Image(systemName: "arrow.counterclockwise") }
                .help("Signal zurücksetzen (r)")
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
