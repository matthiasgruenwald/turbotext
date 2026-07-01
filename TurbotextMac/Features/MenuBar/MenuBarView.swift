import AppKit
import SwiftUI

struct MainContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct MainContentWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct MenuBarView: View {
    @Bindable var appState: AppState
    @State var settingsContentHeight: CGFloat = 0
    @State private var mainContentHeight: CGFloat = 0
    @State private var mainContentWidth: CGFloat = 0
    @State var showInputMonitoringDismissConfirmation = false

    private static let settingsChromeHeight: CGFloat = 140
    private static let settingsMinHeight: CGFloat = 420
    private static let mainMinHeight: CGFloat = 480
    private static let mainMinWidth: CGFloat = 340
    private static let mainMaxWidth: CGFloat = 460
    private static let screenMarginFraction: CGFloat = 0.9

    private var settingsHeight: CGFloat {
        let screenHeight = NSScreen.main?.visibleFrame.height ?? 900
        return PopoverSizing.clampedHeight(
            contentHeight: settingsContentHeight,
            chrome: Self.settingsChromeHeight,
            screenHeight: screenHeight,
            minHeight: Self.settingsMinHeight,
            screenMarginFraction: Self.screenMarginFraction
        )
    }

    private var mainWidth: CGFloat {
        PopoverSizing.clampedWidth(
            contentWidth: mainContentWidth,
            minWidth: Self.mainMinWidth,
            maxWidth: Self.mainMaxWidth
        )
    }

    private var mainHeight: CGFloat {
        let screenHeight = NSScreen.main?.visibleFrame.height ?? 900
        return PopoverSizing.clampedHeight(
            contentHeight: mainContentHeight,
            chrome: 0,
            screenHeight: screenHeight,
            minHeight: Self.mainMinHeight,
            screenMarginFraction: Self.screenMarginFraction
        )
    }

    private var preferredSize: CGSize {
        switch appState.page {
        case .settings:
            return CGSize(width: 680, height: settingsHeight)
        case .main:
            return CGSize(width: mainWidth, height: mainHeight)
        case .onboarding, .workflow:
            return CGSize(width: Self.mainMinWidth, height: Self.mainMinHeight)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            switch appState.page {
            case .main:
                mainPage
            case .onboarding:
                onboardingPage
            case .settings:
                settingsPage
            case .workflow:
                workflowPage
            }
        }
        .frame(width: preferredSize.width, height: preferredSize.height)
        // Hidden, unconstrained copy purely to measure the main page's natural
        // content width (e.g. a workflow row with three hotkey badges needs
        // more horizontal space than the minimum window width).
        .background(
            mainPage
                .fixedSize()
                .opacity(0)
                .allowsHitTesting(false)
                .background(
                    GeometryReader { geometry in
                        Color.clear.preference(key: MainContentWidthKey.self, value: geometry.size.width)
                    }
                )
        )
        .onPreferenceChange(MainContentWidthKey.self) { mainContentWidth = $0 }
        // Hidden copy at the resolved width purely to measure the main page's
        // natural content height (toggle/banners can change row count and thus height).
        .background(
            mainPage
                .frame(width: mainWidth, alignment: .topLeading)
                .fixedSize(horizontal: false, vertical: true)
                .opacity(0)
                .allowsHitTesting(false)
                .background(
                    GeometryReader { geometry in
                        Color.clear.preference(key: MainContentHeightKey.self, value: geometry.size.height)
                    }
                )
        )
        .onPreferenceChange(MainContentHeightKey.self) { mainContentHeight = $0 }
        .animation(.easeInOut(duration: 0.2), value: appState.page)
        .onChange(of: preferredSize) { _, newSize in
            appState.onPreferredContentSizeChange?(newSize)
        }
        .onAppear {
            appState.onPreferredContentSizeChange?(preferredSize)
        }
        .confirmationDialog(
            "Hinweis weiterhin anzeigen?",
            isPresented: $showInputMonitoringDismissConfirmation,
            titleVisibility: .visible
        ) {
            Button("Nicht mehr anzeigen", role: .destructive) {
                appState.dismissInputMonitoringHintPermanently()
            }
            Button("Weiterhin anzeigen", role: .cancel) {}
        } message: {
            Text("Du findest den Status jederzeit unter Einstellungen → App-Verwaltung.")
        }
    }

    // MARK: - Main Page

    private var mainPage: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 0) {
                // Top bar
                HStack {
                    HStack(spacing: 6) {
                        Text("Turbotext")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)

                        Text("macOS Preview")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(.quaternary)
                    }

                    Spacer()

                    NetworkStatusDot(service: appState.networkPingService)

                    Button {
                        appState.page = .settings
                    } label: {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "gear")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.tertiary)
                                .frame(width: 28, height: 28)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.primary.opacity(0.00001)) // hit target
                                )
                                .contentShape(Rectangle())

                            if !appState.accessibilityPermissionGranted {
                                Circle()
                                    .fill(Color.orange)
                                    .frame(width: 6, height: 6)
                                    .offset(x: -4, y: 4)
                            }
                        }
                    }
                    .buttonStyle(SubtleButtonStyle())
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)

                // Status area
                if appState.isConfigured {
                    configuredHeader
                } else {
                    unconfiguredHeader
                }
            }
            .padding(.bottom, 16)
            .background(
                Color(nsColor: .controlBackgroundColor).opacity(0.5)
            )

            if TurbotextInstallLocationService.shouldOfferMoveToApplications {
                installHintBanner
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 6)
            }

            transcriptionModePanel
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, appState.accessibilityPermissionGranted ? 6 : 4)

            if !appState.accessibilityPermissionGranted {
                accessibilityHintBanner
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
            }

            if appState.shouldShowInputMonitoringHint {
                inputMonitoringHintBanner
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
            }

            if let banner = appState.groqFallbackBannerContent {
                groqFallbackBanner(title: banner.title, detail: banner.detail)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
            }

            if let hint = appState.onlineKeyHintBannerContent {
                onlineKeyHintBanner(title: hint.title, detail: hint.detail)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
            }

            // Workflow list
            VStack(spacing: 0) {
                ForEach(WorkflowType.mainMenuCases) { type in
                    let enabled = appState.isWorkflowAvailable(type)
                    WorkflowRowView(
                        type: type,
                        enabled: enabled,
                        shortcuts: appState.shortcutStore.shortcuts(for: type),
                        customName: appState.displayName(for: type),
                        subtitle: appState.workflowSubtitle(for: type)
                    ) {
                        appState.startWorkflow(type)
                    }
                }
            }
            .padding(.vertical, 2)

            Spacer(minLength: 0)

            appFooter
        }
    }

    private var transcriptionModePanel: some View {
        let modelOptions = LocalTranscriptionService.modelOptions()
        let selectedModelInstalled = appState.selectedLocalModelIsInstalled
        let modeStatus = appState.transcriptionModeStatus

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: modeStatus.panelIconName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(iconColor(for: modeStatus.panelIconTone))
                    .frame(width: 22, height: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(modeStatus.panelTitle)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.primary)

                    Text(modeStatus.panelSubtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 4)

                // .help() doesn't fire on a disabled control's own hover (macOS stops
                // tracking mouse on disabled views), so the tooltip lives on this
                // always-hit-testable wrapper instead of on the Toggle itself.
                let isToggleDisabled = appState.isDownloadingLocalModel
                    || !OnlineModeToggle.isToggleEnabled(
                        secureLocalModeEnabled: appState.appSettings.secureLocalModeEnabled,
                        localModelInstalled: selectedModelInstalled
                    )
                Group {
                    Toggle("", isOn: Binding(
                        get: { !appState.appSettings.secureLocalModeEnabled },
                        set: { requestedOnline in
                            guard let next = OnlineModeToggle.nextSecureLocalModeEnabled(
                                requestedOnline: requestedOnline,
                                localModelInstalled: selectedModelInstalled
                            ) else { return }
                            if next {
                                appState.enableSecureLocalMode()
                            } else {
                                appState.appSettings.secureLocalModeEnabled = false
                            }
                        }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .disabled(isToggleDisabled)
                    .opacity(isToggleDisabled ? 0.4 : 1.0)
                }
                .contentShape(Rectangle())
                .help(
                    OnlineModeToggle.disabledReason(
                        secureLocalModeEnabled: appState.appSettings.secureLocalModeEnabled,
                        localModelInstalled: selectedModelInstalled
                    ) ?? ""
                )
            }

            if appState.appSettings.secureLocalModeEnabled {
                HStack(spacing: 8) {
                    Text("Modell")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)

                    Picker("", selection: Binding(
                        get: { appState.selectedLocalModelName },
                        set: { appState.appSettings.selectedLocalTranscriptionModelName = $0 }
                    )) {
                        ForEach(modelOptions) { model in
                            Text(model.shortDisplayName).tag(model.id)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                    .controlSize(.small)
                    .disabled(appState.isDownloadingLocalModel)
                }

                if let progress = appState.localModelDownloadProgress {
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView(value: progress)
                        Text(appState.localModelDownloadStatusText ?? "Modell wird geladen...")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }
                } else if !selectedModelInstalled {
                    Button(appState.localModelDownloadButtonTitle) {
                        appState.installSelectedLocalModel()
                    }
                    .controlSize(.small)
                }

                if let errorText = appState.localModelDownloadErrorText {
                    Text(errorText)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
    }

    private func iconColor(for tone: TranscriptionModeIconTone) -> Color {
        switch tone {
        case .local:
            return .green
        case .groq:
            return .blue
        case .fallback:
            return .secondary
        }
    }

    private var configuredHeader: some View {
        HStack(spacing: 8) {
            Button {
                appState.openMicrophoneSettings()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(appState.activeMicrophoneDisplayName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .buttonStyle(SubtleButtonStyle())

            Circle()
                .fill(.green)
                .frame(width: 7, height: 7)
            Text("Bereit")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
        }
    }

    private var unconfiguredHeader: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.1))
                    .frame(width: 40, height: 40)
                Image(systemName: "key.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.orange)
            }

            VStack(spacing: 4) {
                Text("Einrichtung n\u{00F6}tig")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)

                Text("\u{00D6}ffne die Einstellungen und hinterlege deine Zugangsdaten, um loszulegen.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)
            }

            Button {
                appState.page = .settings
            } label: {
                Text("Einstellungen \u{00F6}ffnen")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.primary.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                    )
            }
            .buttonStyle(SubtleButtonStyle())
        }
    }

    var appFooter: some View {
        HStack {
            Spacer()
            Button("Beenden") {
                NSApplication.shared.terminate(nil)
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
            .buttonStyle(SubtleButtonStyle())
            Spacer()
        }
        .padding(.vertical, 8)
    }
}
