import SwiftUI
import AppKit

struct SettingsContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        // Every view in the tree implicitly contributes defaultValue (0) through
        // this reduce chain; overwriting would let an unrelated sibling stomp the
        // real measurement. Keep the largest value seen instead.
        value = max(value, nextValue())
    }
}

struct SettingsContentView: View {
    @Bindable var appState: AppState
    @State private var selectedSection: SettingsSection = .transcription
    @Binding var measuredContentHeight: CGFloat

    private static let sidebarWidth: CGFloat = 150
    private static let contentAreaWidth: CGFloat = 680 - sidebarWidth - 1

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebarView(selectedSection: $selectedSection)

            Divider()

            ScrollView {
                sectionView(for: selectedSection)
            }
            .frame(maxWidth: .infinity)
        }
        // Hidden, unconstrained copy purely to measure the section's natural height:
        // the visible copy above lives inside a ScrollView whose own height is driven
        // by this same measurement, so measuring it directly would be circular.
        .background(
            sectionView(for: selectedSection)
                .frame(width: Self.contentAreaWidth, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .opacity(0)
                .allowsHitTesting(false)
                .background(
                    GeometryReader { geometry in
                        Color.clear.preference(key: SettingsContentHeightKey.self, value: geometry.size.height)
                    }
                )
        )
        .onPreferenceChange(SettingsContentHeightKey.self) { measuredContentHeight = $0 }
        .onAppear {
            appState.refreshAccessibilityPermission()
            if let requestedSection = appState.requestedSettingsSection {
                selectedSection = requestedSection
                appState.requestedSettingsSection = nil
            } else {
                selectedSection = SettingsSection.defaultSection(
                    accessibilityPermissionGranted: appState.accessibilityPermissionGranted
                )
            }
        }
    }

    @ViewBuilder
    private func sectionView(for section: SettingsSection) -> some View {
        switch section {
        case .transcription:
            TranscriptionSettingsView(appState: appState)
        case .workflows:
            WorkflowsSettingsView(appState: appState)
        case .shortcuts:
            ShortcutsSettingsView(appState: appState)
        case .credentials:
            CredentialsSettingsView(appState: appState)
        case .appManagement:
            AppManagementSettingsView(appState: appState)
        }
    }
}

// MARK: - Sidebar

private struct SettingsSidebarView: View {
    @Binding var selectedSection: SettingsSection

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(SettingsSection.allCases) { section in
                Button {
                    selectedSection = section
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: section.iconName)
                            .font(.system(size: 11.5, weight: .medium))
                            .frame(width: 16)
                        Text(section.title)
                            .font(.system(size: 11.5, weight: selectedSection == section ? .semibold : .regular))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(selectedSection == section ? .primary : .secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(selectedSection == section ? Color.primary.opacity(0.06) : Color.clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(SubtleButtonStyle())
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(width: 150)
    }
}

// MARK: - Section Label (quiet style)

struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
    }
}
