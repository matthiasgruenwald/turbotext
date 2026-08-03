import AppKit
import SwiftUI

extension PermissionGuideStep {
    var guideTitle: String {
        switch self {
        case .accessibility:
            return "Bedienungshilfen freigeben"
        case .inputMonitoring:
            return "Eingabeüberwachung freigeben"
        }
    }

    var guideText: String {
        switch self {
        case .accessibility:
            return "Die Systemeinstellungen sind geöffnet. Ziehe Turbotext unten in die Liste „Bedienungshilfen“."
        case .inputMonitoring:
            return "Die Systemeinstellungen sind geöffnet. Ziehe Turbotext unten in die Liste „Eingabeüberwachung“."
        }
    }
}

struct PermissionGuideView: View {
    var coordinator: PermissionGuideCoordinator

    private var dragURL: URL { PermissionGuideDragSource.url() }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if let step = coordinator.currentStep {
                VStack(alignment: .leading, spacing: 4) {
                    Text(step.guideTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(step.guideText)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            dragToken

            HStack {
                if coordinator.canSkipCurrentStep {
                    Button("Überspringen") {
                        coordinator.skipCurrentStep()
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .buttonStyle(.plain)
                }

                Spacer()

                Button("Abbrechen") {
                    coordinator.cancel()
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(width: 292)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Berechtigung einrichten")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)

            Spacer()

            Text("Schritt \(coordinator.progressLabel)")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)

            Button {
                coordinator.cancel()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var dragToken: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: dragURL.path))
                .resizable()
                .interpolation(.high)
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text("Turbotext")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                Label("Ziehen und in der Liste ablegen", systemImage: "hand.point.up.left")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.secondary.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        )
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onDrag { NSItemProvider(object: dragURL as NSURL) }
    }
}
