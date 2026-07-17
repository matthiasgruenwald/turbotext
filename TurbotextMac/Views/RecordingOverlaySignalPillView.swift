import SwiftUI

/// Dark, non-interactive signal pill shown near the insertion caret while a
/// voice workflow records and processes. Visual language matches variant A
/// ("Signal-Pille") from the throwaway CursorWaveformVisualPrototype.
struct RecordingOverlaySignalPillView: View {
    let phase: RecordingOverlayPhase
    let levelHistory: [Float]

    var body: some View {
        HStack(spacing: 12) {
            switch phase {
            case .hidden:
                EmptyView()
            case .recording:
                Circle().fill(.red).frame(width: 9, height: 9)
                WaveformBars(levelHistory: levelHistory)
            case .processing:
                ProgressView().controlSize(.small).tint(.white)
                Text("Wird verarbeitet …")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(minWidth: phase == .recording ? 180 : 0)
        .background(Color(red: 0.13, green: 0.15, blue: 0.20))
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.35), radius: 14, y: 8)
        .fixedSize()
    }
}

private struct WaveformBars: View {
    let levelHistory: [Float]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(levelHistory.enumerated()), id: \.offset) { index, level in
                Capsule()
                    .fill(.white.opacity(0.85))
                    .frame(width: 3, height: barHeight(for: level))
            }
        }
        .frame(height: 20)
    }

    private func barHeight(for level: Float) -> CGFloat {
        4 + CGFloat(level) * 16
    }
}
