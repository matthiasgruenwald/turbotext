import SwiftUI

struct NetworkStatusDot: View {
    @Bindable var service: NetworkPingService
    @State private var isHovering = false

    var body: some View {
        ZStack(alignment: .trailing) {
            if isHovering {
                Text(NetworkStatusIndicator.hoverText(
                    averageLatencyMs: service.averageLatencyMs,
                    packetLossPercent: service.packetLossPercent
                ))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6))
                .fixedSize()
                .offset(x: -18)
                .transition(.opacity)
            }

            Circle()
                .fill(NetworkStatusIndicator.color(for: service.status).opacity(0.55))
                .frame(width: 6, height: 6)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .help(NetworkStatusIndicator.statusLabel(for: service.status))
        .onHover { hovering in
            isHovering = hovering
        }
        .animation(.easeOut(duration: 0.1), value: isHovering)
    }
}

enum NetworkStatusIndicator {
    static func color(for status: NetworkQualityStatus) -> Color {
        switch status {
        case .green: return .green
        case .yellow: return .yellow
        case .red: return .red
        }
    }

    static func hoverText(averageLatencyMs: Double?, packetLossPercent: Double) -> String {
        guard let averageLatencyMs else {
            return "Keine Verbindung"
        }
        return "\(Int(averageLatencyMs.rounded())) ms · \(Int(packetLossPercent.rounded()))% Verlust"
    }

    static func statusLabel(for status: NetworkQualityStatus) -> String {
        switch status {
        case .green: return "Online"
        case .yellow: return "Eingeschränkte Verbindung"
        case .red: return "Keine Verbindung"
        }
    }
}
