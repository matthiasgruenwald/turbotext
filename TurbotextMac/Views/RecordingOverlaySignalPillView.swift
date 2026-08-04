import SwiftUI

struct RecordingOverlaySignalPillView: View {
    static let width: CGFloat = 260
    static let minHeight: CGFloat = 44

    let phase: RecordingOverlayPhase
    let levelHistory: [Float]
    var showsSilenceHint: Bool = false
    var signalReceived: Bool = false
    var errorMessage: String?
    var liveTranscript: LiveTranscriptDisplay?
    var transcriptionLag: TimeInterval?
    var processingLabel: String?
    var completionLabel: String?
    var onDismissError: () -> Void = {}
    var onDismissBergungError: () -> Void = {}
    var onDismissPasteError: () -> Void = {}
    var onDismissCompletionLabel: () -> Void = {}

    var body: some View {
        content
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(width: Self.width)
            .frame(minHeight: Self.minHeight)
            // The green "signal received" tint (#154) blended translucent white text
            // below WCAG AA contrast; the red recording dot already signals recording
            // state, so the pill now stays on the one background for every phase.
            .background(Color(red: 0.13, green: 0.15, blue: 0.20))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.35), radius: 14, y: 8)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .onTapGesture {
                switch phase {
                case .error:
                    onDismissError()
                case .bergungError:
                    onDismissBergungError()
                case .pasteError:
                    onDismissPasteError()
                case .completion:
                    onDismissCompletionLabel()
                default:
                    break
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .hidden:
            EmptyView()
        case .recording:
            recordingContent
        case .processing:
            // #158: the frozen strip stays visible through the drain/processing
            // phase instead of vanishing, so the pill never looks dead mid-Nachlauf.
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 12) {
                    ProgressView().controlSize(.small).tint(.white).padding(.top, 2)
                    if let liveTranscript, !liveTranscript.isEmpty {
                        liveTranscriptText(liveTranscript)
                    } else {
                        Text(processingLabel ?? "Wird verarbeitet …")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                }
                WaveformBars(
                    levelHistory: levelHistory,
                    transcriptionLag: transcriptionLag,
                    unheardBarColor: .white.opacity(0.28)
                )
                .frame(maxWidth: .infinity)
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
        case .bergungError:
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                VStack(alignment: .leading, spacing: 2) {
                    Text(errorMessage ?? "Aufnahme beendet, gesicherte Teile eingefügt.")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text("Ohne finale Nachbearbeitung")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                }
            }
        case .pasteError:
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                Text(errorMessage ?? "Einfügen fehlgeschlagen – Text ist in der Zwischenablage")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white)
                    .lineLimit(2)
            }
        case .completion:
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(completionLabel ?? "")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white)
                    .lineLimit(2)
            }
        }
    }

    // #158: transcript and waveform are no longer either/or — the level strip hangs
    // on the microphone, not the engine, so it is the one indicator that cannot stall.
    @ViewBuilder
    private var recordingContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 12) {
                Circle().fill(.red).frame(width: 9, height: 9).padding(.top, 4)
                if showsSilenceHint {
                    Text("Kein Signal erkannt …")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                } else if let liveTranscript, !liveTranscript.isEmpty {
                    liveTranscriptText(liveTranscript)
                }
            }
            // Green = capture is live; the processing phase keeps the frozen white strip.
            // The dim tail marks audio the engine has not decoded yet (#158 package 4).
            WaveformBars(
                levelHistory: levelHistory,
                barColor: .green.opacity(0.9),
                transcriptionLag: transcriptionLag,
                unheardBarColor: .green.opacity(0.28)
            )
            .frame(maxWidth: .infinity)
        }
    }

    private func liveTranscriptText(_ display: LiveTranscriptDisplay) -> some View {
        TailClippedTranscriptText(text: transcriptText(display), maxLines: display.maxLines)
    }

    private func transcriptText(_ display: LiveTranscriptDisplay) -> Text {
        var result = Text(display.finalText)
            .font(.footnote.weight(.medium))
            .foregroundColor(.white)
        if !display.volatileText.isEmpty {
            let separator = display.finalText.isEmpty ? "" : " "
            result = result
                + Text(separator + display.volatileText)
                    .font(.footnote.weight(.medium))
                    .foregroundColor(.white.opacity(0.72))
        }
        return result
    }
}

/// Reserves height exactly as `.lineLimit` would (growing up to `maxLines`,
/// capped there), then overlays the untruncated text bottom-aligned and
/// clipped to that measured height, so the newest text (tail) stays visible
/// instead of `.lineLimit`'s default head-truncation. `.frame(maxHeight:)`
/// alone doesn't clamp a `.fixedSize` child back down to the offered size, so
/// the reserved height is measured explicitly and applied as a fixed height.
private struct TailClippedTranscriptText: View {
    let text: Text
    let maxLines: Int
    @State private var reservedHeight: CGFloat?

    var body: some View {
        text
            .lineLimit(maxLines)
            .hidden()
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: ReservedHeightKey.self, value: proxy.size.height)
                }
            )
            .onPreferenceChange(ReservedHeightKey.self) { reservedHeight = $0 }
            .overlay(alignment: .bottomLeading) {
                text
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(height: reservedHeight, alignment: .bottom)
                    .clipped()
            }
    }
}

private struct ReservedHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct WaveformBars: View {
    let levelHistory: [Float]
    var barColor: Color = .white.opacity(0.85)
    var transcriptionLag: TimeInterval?
    var unheardBarColor: Color?

    var body: some View {
        Canvas { context, size in
            let capacity = RecordingOverlayState.levelHistoryLimit
            guard capacity > 0 else { return }
            let unheardBars = min(
                RecordingOverlayState.unheardBarCount(forLag: transcriptionLag) ?? 0,
                levelHistory.count
            )
            let heardSplit = levelHistory.count - unheardBars
            let pendingColor = unheardBarColor ?? barColor
            let slot = size.width / CGFloat(capacity)
            let barWidth = max(1, slot * 0.55)
            let startX = size.width - CGFloat(levelHistory.count) * slot
            for (index, level) in levelHistory.enumerated() {
                let x = startX + CGFloat(index) * slot + (slot - barWidth) / 2
                guard x + barWidth >= 0 else { continue }
                let height = barHeight(for: level)
                let rect = CGRect(x: x, y: (size.height - height) / 2, width: barWidth, height: height)
                let path = Path(roundedRect: rect, cornerRadius: barWidth / 2)
                context.fill(path, with: .color(index < heardSplit ? barColor : pendingColor))
            }
        }
        .frame(height: 30)
        .clipped()
    }

    private func barHeight(for level: Float) -> CGFloat {
        3 + CGFloat(level) * 27
    }
}
