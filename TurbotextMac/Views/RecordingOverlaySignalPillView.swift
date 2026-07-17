import SwiftUI

/// Dark, non-interactive signal pill shown near the insertion caret while a
/// voice workflow records and processes. Visual language matches variant A
/// ("Signal-Pille") from the throwaway CursorWaveformVisualPrototype.
///
/// The outer capsule always renders at a fixed size (`width`/`height`), no matter
/// which phase or sub-state is shown — content that appears/disappears inside it
/// (silence hint, error text) must never resize or reflow the pill.
struct RecordingOverlaySignalPillView: View {
    static let width: CGFloat = 260
    static let height: CGFloat = 44

    let phase: RecordingOverlayPhase
    let levelHistory: [Float]
    var showsSilenceHint: Bool = false
    var errorMessage: String?
    var onDismissError: () -> Void = {}

    var body: some View {
        content
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(width: Self.width, height: Self.height)
            .background(Color(red: 0.13, green: 0.15, blue: 0.20))
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.35), radius: 14, y: 8)
            .contentShape(Capsule())
            .onTapGesture {
                guard phase == .error else { return }
                onDismissError()
            }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .hidden:
            EmptyView()
        case .recording:
            HStack(spacing: 12) {
                Circle().fill(.red).frame(width: 9, height: 9)
                if showsSilenceHint {
                    Text("Kein Signal erkannt …")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                } else {
                    WaveformBars(levelHistory: levelHistory)
                        .frame(maxWidth: .infinity)
                }
            }
        case .processing:
            HStack(spacing: 12) {
                ProgressView().controlSize(.small).tint(.white)
                Text("Wird verarbeitet …")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white)
            }
        case .error:
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                Text(errorMessage ?? "Aufnahme konnte nicht gestartet werden.")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white)
                    .lineLimit(2)
            }
        }
    }
}

/// Draws bars directly into a `Canvas` rather than one view per sample — cheap
/// per-frame redraws and, more importantly, a slot width derived from the
/// fixed `RecordingOverlayState.levelHistoryLimit` rather than the current
/// sample count. Early in a recording (few samples) that leaves the window
/// mostly empty with bars only at the right edge; new samples enter from the
/// right and, once the window fills, older bars land past x=0 and are
/// skipped — reading as the waveform scrolling left and clipping off.
/// Chosen over per-view HStack approaches (variant "C" of
/// docs/research prototype `WaveformScrollPrototype`) because it isn't
/// sensitive to SwiftUI's HStack/GeometryReader layout timing.
private struct WaveformBars: View {
    let levelHistory: [Float]

    var body: some View {
        Canvas { context, size in
            let capacity = RecordingOverlayState.levelHistoryLimit
            guard capacity > 0 else { return }
            let slot = size.width / CGFloat(capacity)
            let barWidth = max(1, slot * 0.55)
            let startX = size.width - CGFloat(levelHistory.count) * slot
            for (index, level) in levelHistory.enumerated() {
                let x = startX + CGFloat(index) * slot + (slot - barWidth) / 2
                guard x + barWidth >= 0 else { continue }
                let height = barHeight(for: level)
                let rect = CGRect(x: x, y: (size.height - height) / 2, width: barWidth, height: height)
                let path = Path(roundedRect: rect, cornerRadius: barWidth / 2)
                context.fill(path, with: .color(.white.opacity(0.85)))
            }
        }
        .frame(height: 20)
        .clipped()
    }

    private func barHeight(for level: Float) -> CGFloat {
        4 + CGFloat(level) * 16
    }
}
