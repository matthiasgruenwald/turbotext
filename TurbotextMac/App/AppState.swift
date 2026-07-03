import SwiftUI
import Observation
import AppKit

enum PopoverPage: Equatable {
    case main
    case onboarding
    case settings
    case workflow
}

@Observable
@MainActor
final class AppState {
    let settingsState: SettingsState
    let workflowLifecycle: WorkflowLifecycleManager
    let quotaAndFallback: QuotaAndFallbackState
    let microphoneState: MicrophoneState

    var orchestrator: WorkflowOrchestrator { workflowLifecycle.orchestrator }
    var activeWorkflow: (any Workflow)? { workflowLifecycle.activeWorkflow }
    var currentPhase: WorkflowPhase { workflowLifecycle.currentPhase }

    var page: PopoverPage = .main {
        didSet {
            guard oldValue != page else { return }
            onCloudIndicatorRefreshNeeded?()
        }
    }
    var isPopoverShown = false
    var menuBarStatus: MenuBarStatus = .idle {
        didSet {
            guard oldValue != menuBarStatus else { return }
            onMenuBarStatusChange?(menuBarStatus)
        }
    }
    var accessibilityPermissionGranted = false {
        didSet {
            guard oldValue != accessibilityPermissionGranted else { return }
            onCloudIndicatorRefreshNeeded?()
        }
    }
    var inputMonitoringPermissionGranted = false {
        didSet {
            guard oldValue != inputMonitoringPermissionGranted else { return }
            onCloudIndicatorRefreshNeeded?()
        }
    }
    var localModelDownloadProgress: Double?
    var localModelDownloadStatusText: String?
    var localModelDownloadErrorText: String?
    var onMenuBarStatusChange: ((MenuBarStatus) -> Void)?
    var onPreferredContentSizeChange: ((CGSize) -> Void)?
    var onCloudIndicatorRefreshNeeded: (() -> Void)?
    var requestedSettingsSection: SettingsSection?
    private var lastPopoverPasteTarget: PasteTarget?
    private var isCheckingGroqQuota = false
    private let cloudTranscriptionRouter: CloudTranscriptionRouter

    // Persisted settings (delegated to `settingsState`)
    var appSettings: AppSettings {
        get { settingsState.appSettings }
        set { settingsState.appSettings = newValue }
    }
    var transcriptionSettings: TranscriptionSettings {
        get { settingsState.transcriptionSettings }
        set { settingsState.transcriptionSettings = newValue }
    }
    var textImprovementSettings: TextImprovementSettings {
        get { settingsState.textImprovementSettings }
        set { settingsState.textImprovementSettings = newValue }
    }
    var dampfAblassenSettings: DampfAblassenSettings {
        get { settingsState.dampfAblassenSettings }
        set { settingsState.dampfAblassenSettings = newValue }
    }
    var emojiTextSettings: EmojiTextSettings {
        get { settingsState.emojiTextSettings }
        set { settingsState.emojiTextSettings = newValue }
    }

    // Hotkeys
    let shortcutStore: ShortcutStore
    let hotkeyService: HotkeyService

    // Microphone favorites (delegated to `microphoneState`)
    var microphoneFavoritesStore: MicrophoneFavoritesStore { microphoneState.favoritesStore }

    // Network status
    let networkPingService: NetworkPingService

    // Computed
    var isConfigured: Bool {
        KeychainService.isConfigured || !LocalTranscriptionService.installedModels().isEmpty
    }
    var shouldShowOnboarding: Bool {
        !isConfigured && !appSettings.hasSeenOnboarding
    }
    var groqOnboardingState: GroqOnboardingState {
        GroqOnboardingState.resolve(hasGroqKey: KeychainService.load(key: .groqAPIKey) != nil)
    }

    func openMicrophoneSettings() {
        requestedSettingsSection = .transcription
        page = .settings
    }

    var activeMicrophoneDisplayName: String {
        microphoneState.activeDeviceDisplayName
    }

    init(quotaManager: QuotaManager = GroqQuotaManager.shared) {
        self.quotaAndFallback = QuotaAndFallbackState(quotaManager: quotaManager)
        self.cloudTranscriptionRouter = CloudTranscriptionRouter(quotaManager: quotaManager)
        let store = ShortcutStore()
        self.shortcutStore = store
        self.hotkeyService = HotkeyService(store: store)
        self.microphoneState = MicrophoneState()
        self.networkPingService = NetworkPingService()
        self.settingsState = SettingsState()

        let lifecycle = WorkflowLifecycleManager(workflowFactory: { _, _ in nil })
        self.workflowLifecycle = lifecycle
        lifecycle.isPopoverShown = { [weak self] in self?.isPopoverShown ?? false }

        lifecycle.workflowFactory = { [weak self] type, backendOverride in
            self?.makeWorkflow(type, backendOverride: backendOverride)
        }
        lifecycle.orchestrator.onPasteTargetActivationNeeded = { target in
            target.application.activate(options: [])
        }
        lifecycle.orchestrator.onWorkflowOutput = { [weak self] _ in
            self?.onCloudIndicatorRefreshNeeded?()
        }
        lifecycle.onPageChangeNeeded = { [weak self] page in
            self?.page = page
        }
        lifecycle.orchestrator.onMenuBarStatusChange = { [weak self] status in
            self?.menuBarStatus = status
        }
        lifecycle.orchestrator.onAccessibilityPermissionChange = { [weak self] granted in
            self?.accessibilityPermissionGranted = granted
        }
        lifecycle.onWillPaste = { [weak self] in
            guard self?.isPopoverShown == true else { return }
            NotificationCenter.default.post(name: .dismissPopover, object: nil)
        }

        settingsState.onAppSettingsChanged = { [weak self] oldValue, newValue in
            guard let self else { return }
            self.prewarmLocalTranscriptionIfNeeded()
            self.onCloudIndicatorRefreshNeeded?()
            if oldValue.dockModeEnabled != newValue.dockModeEnabled {
                DockModeService.apply(dockModeEnabled: newValue.dockModeEnabled)
            }
        }

        refreshAccessibilityPermission()
        autoSelectFastLocalModelIfNeeded()
        prewarmLocalTranscriptionIfNeeded()
        microphoneState.start()
        networkPingService.start()
        checkGroqQuotaIfNeeded()
    }

    func checkGroqQuotaIfNeeded() {
        guard !isCheckingGroqQuota else { return }
        isCheckingGroqQuota = true
        Task { @MainActor [weak self] in
            defer { self?.isCheckingGroqQuota = false }
            guard let self else { return }
            await cloudTranscriptionRouter.checkGroqQuotaIfNeeded(
                secureLocalModeEnabled: appSettings.secureLocalModeEnabled
            )
        }
    }

    // MARK: - Custom Display Names

    func displayName(for type: WorkflowType) -> String {
        switch type {
        case .textImprover:
            let name = textImprovementSettings.customName.trimmingCharacters(in: .whitespaces)
            return name.isEmpty ? type.displayName : name
        case .dampfAblassen:
            let name = dampfAblassenSettings.customName.trimmingCharacters(in: .whitespaces)
            return name.isEmpty ? type.displayName : name
        case .emojiText:
            let name = emojiTextSettings.customName.trimmingCharacters(in: .whitespaces)
            return name.isEmpty ? type.displayName : name
        default:
            return type.displayName
        }
    }

    var groqFallbackBannerContent: (title: String, detail: String)? {
        quotaAndFallback.fallbackBannerContent(secureLocalModeEnabled: appSettings.secureLocalModeEnabled)
    }

    var onlineKeyHintBannerContent: (title: String, detail: String)? {
        OnlineKeyHintBanner.content(
            secureLocalModeEnabled: appSettings.secureLocalModeEnabled,
            hasAnyAPIKey: KeychainService.load(key: .openAIAPIKey) != nil
                || KeychainService.load(key: .groqAPIKey) != nil
        )
    }

    var transcriptionModeStatus: TranscriptionModeStatus {
        TranscriptionModeStatus(
            secureLocalModeEnabled: appSettings.secureLocalModeEnabled,
            selectedLocalModelInstalled: selectedLocalModelIsInstalled,
            selectedLocalModelDisplayName: selectedLocalModelDisplayName,
            isDownloadingLocalModel: isDownloadingLocalModel,
            localModelDownloadStatusText: localModelDownloadStatusText,
            hasGroqKey: KeychainService.load(key: .groqAPIKey) != nil,
            groqFallbackActive: quotaAndFallback.fallbackActive,
            groqQuotaUsedToday: quotaAndFallback.formattedUsedToday
        )
    }

    func workflowSubtitle(for type: WorkflowType) -> String {
        switch type {
        case .transcription:
            return transcriptionModeStatus.transcriptionWorkflowSubtitle
        case .localTranscription:
            return "Nur lokal. Kein Server."
        case .textImprover, .dampfAblassen, .emojiText:
            if appSettings.secureLocalModeEnabled {
                return "Im lokalen Modus pausiert."
            }
            return type.subtitle
        }
    }

    var resolvedLocalModelName: String {
        LocalTranscriptionService.resolvedModelName(appSettings.selectedLocalTranscriptionModelName)
    }

    var selectedLocalModelDisplayName: String {
        LocalTranscriptionModel.displayName(for: selectedLocalModelName)
    }

    var selectedLocalModelName: String {
        LocalTranscriptionService.normalizedModelName(appSettings.selectedLocalTranscriptionModelName)
    }

    var selectedLocalModelIsInstalled: Bool {
        LocalTranscriptionService.isModelInstalled(selectedLocalModelName)
    }

    var isDownloadingLocalModel: Bool {
        localModelDownloadProgress != nil
    }

    var localModelDownloadButtonTitle: String {
        selectedLocalModelIsInstalled
            ? "\(LocalTranscriptionModel.displayName(for: selectedLocalModelName)) ist installiert"
            : "\(LocalTranscriptionModel.displayName(for: selectedLocalModelName)) installieren"
    }

    // MARK: - Workflow Management

    func startWorkflow(
        _ type: WorkflowType,
        source: WorkflowLaunchSource = .manual,
        backendOverride: TranscriptionBackend? = nil
    ) {
        workflowLifecycle.start(
            type,
            source: source,
            isAvailable: isWorkflowAvailable(type),
            backendOverride: backendOverride,
            pasteTarget: capturePasteTarget(for: source)
        )
    }

    private func makeWorkflow(
        _ type: WorkflowType,
        backendOverride: TranscriptionBackend?
    ) -> (any Workflow)? {
        switch type {
        case .transcription:
            let backend = backendOverride ?? (appSettings.secureLocalModeEnabled ? .local : .remote)
            return TranscriptionWorkflow(
                customTerms: textImprovementSettings.customTerms,
                language: transcriptionSettings.language,
                backend: backend,
                transcriber: transcriber(for: backend)
            )
        case .localTranscription:
            return TranscriptionWorkflow(
                type: .localTranscription,
                customTerms: textImprovementSettings.customTerms,
                language: transcriptionSettings.language,
                backend: .local,
                transcriber: transcriber(for: .local)
            )
        case .textImprover:
            return TextImprovementWorkflow(
                settings: textImprovementSettings,
                language: transcriptionSettings.language,
                providerMode: appSettings.rewritingProviderMode,
                transcriber: transcriber(for: .remote)
            )
        case .dampfAblassen:
            return DampfAblassenWorkflow(
                settings: dampfAblassenSettings,
                customTerms: textImprovementSettings.customTerms,
                language: transcriptionSettings.language,
                providerMode: appSettings.rewritingProviderMode,
                transcriber: transcriber(for: .remote)
            )
        case .emojiText:
            return EmojiTextWorkflow(
                settings: emojiTextSettings,
                customTerms: textImprovementSettings.customTerms,
                language: transcriptionSettings.language,
                providerMode: appSettings.rewritingProviderMode,
                transcriber: transcriber(for: .remote)
            )
        }
    }

    private func transcriber(for backend: TranscriptionBackend) -> SpokenWorkflowPipeline.Transcriber {
        switch backend {
        case .remote:
            return { [cloudTranscriptionRouter] audioURL, duration, terms, language in
                try await cloudTranscriptionRouter.transcribe(
                    audioURL: audioURL,
                    durationSeconds: duration,
                    customTerms: terms,
                    language: language
                ).text
            }
        case .local:
            let localModelName = selectedLocalModelName
            return { audioURL, _, _, language in
                try await LocalTranscriptionService.shared.transcribe(
                    audioURL: audioURL,
                    language: language,
                    modelName: localModelName
                )
            }
        }
    }

    func isWorkflowAvailable(_ type: WorkflowType) -> Bool {
        switch type {
        case .localTranscription:
            return selectedLocalModelIsInstalled
        case .transcription:
            return transcriptionModeStatus.secureLocalModeEnabled
                ? transcriptionModeStatus.selectedLocalModelInstalled
                : KeychainService.isConfigured
        case .textImprover, .dampfAblassen, .emojiText:
            return !appSettings.secureLocalModeEnabled && KeychainService.isConfigured
        }
    }

    func stopCurrentWorkflow() {
        workflowLifecycle.stop()
    }

    func resetCurrentWorkflow() {
        workflowLifecycle.reset()
        menuBarStatus = .idle
    }

    func enableSecureLocalMode() {
        appSettings.secureLocalModeEnabled = true
        if !selectedLocalModelIsInstalled {
            installSelectedLocalModel()
        }
    }

    func installSelectedLocalModel() {
        guard !isDownloadingLocalModel else { return }

        let modelName = selectedLocalModelName
        localModelDownloadProgress = 0
        localModelDownloadStatusText = "Download startet..."
        localModelDownloadErrorText = nil

        Task {
            do {
                let installedURL = try await LocalTranscriptionService.shared.downloadAndInstall(
                    modelName: modelName
                ) { [weak self] progress in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        let clampedProgress = min(max(progress, 0), 1)
                        self.localModelDownloadProgress = clampedProgress
                        self.localModelDownloadStatusText = "Download \(Int(clampedProgress * 100)) %"
                    }
                }

                appSettings.selectedLocalTranscriptionModelName = installedURL.lastPathComponent
                appSettings.secureLocalModeEnabled = true
                localModelDownloadProgress = nil
                localModelDownloadStatusText = "\(LocalTranscriptionModel.displayName(for: modelName)) ist installiert."
                localModelDownloadErrorText = nil

                try? await LocalTranscriptionService.shared.prepare(modelName: modelName)
            } catch {
                localModelDownloadProgress = nil
                localModelDownloadStatusText = nil
                localModelDownloadErrorText = error.localizedDescription
            }
        }
    }

    func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.declareTypes([.string, Self.concealedPasteboardType], owner: nil)
        pasteboard.setString(text, forType: .string)
        pasteboard.setString("", forType: Self.concealedPasteboardType)
    }

    private static let concealedPasteboardType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")

    func prepareForPopoverPresentation() {
        refreshAccessibilityPermission()
        checkGroqQuotaIfNeeded()
        lastPopoverPasteTarget = captureCurrentFrontmostApp()
        if let activeWorkflow, activeWorkflow.phase.isActive {
            page = .workflow
        } else if shouldShowOnboarding {
            page = .onboarding
            markOnboardingSeen()
        } else if page == .workflow {
            page = .main
        } else if page == .onboarding {
            page = .main
        }
    }

    func markOnboardingSeen() {
        guard !appSettings.hasSeenOnboarding else { return }
        appSettings.hasSeenOnboarding = true
    }

    // MARK: - API Key Status

    func apiKeyDisplayValue(for key: KeychainKey) -> String {
        guard let value = KeychainService.load(key: key), !value.isEmpty else {
            return ""
        }
        if value.count > 8 {
            return String(value.prefix(4)) + " \u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}"
        }
        return "\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}"
    }

    func hasValue(for key: KeychainKey) -> Bool {
        guard let value = KeychainService.load(key: key) else { return false }
        return !value.isEmpty
    }

    private func autoSelectFastLocalModelIfNeeded() {
        guard !appSettings.hasAutoSelectedFastLocalModel,
              LocalTranscriptionService.shouldAutoSelectRecommendedFastModel(
                currentModelName: appSettings.selectedLocalTranscriptionModelName
              ) else {
            return
        }

        appSettings.selectedLocalTranscriptionModelName = LocalTranscriptionService.recommendedFastModelName
        appSettings.hasAutoSelectedFastLocalModel = true
    }

    private func prewarmLocalTranscriptionIfNeeded() {
        guard appSettings.secureLocalModeEnabled,
              LocalTranscriptionService.isModelInstalled(resolvedLocalModelName) else {
            return
        }

        let modelName = resolvedLocalModelName
        Task.detached(priority: .utility) {
            try? await LocalTranscriptionService.shared.prepare(modelName: modelName)
        }
    }

    private func capturePasteTarget(for source: WorkflowLaunchSource) -> PasteTarget? {
        switch source {
        case .manual:
            return lastPopoverPasteTarget
        case .hotkeyBackground:
            return captureCurrentFrontmostApp()
        }
    }

    private func captureCurrentFrontmostApp() -> PasteTarget? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }

        let ownPid = NSRunningApplication.current.processIdentifier
        guard app.processIdentifier != ownPid else { return nil }

        return PasteTarget(
            bundleIdentifier: app.bundleIdentifier,
            processIdentifier: app.processIdentifier,
            application: app
        )
    }
}

// MARK: - Permissions

extension AppState {
    func refreshAccessibilityPermission() {
        accessibilityPermissionGranted = AccessibilityPermissionService.currentStatus()
        inputMonitoringPermissionGranted = InputMonitoringPermissionService.currentStatus()
    }

    func requestAccessibilityPermission() {
        accessibilityPermissionGranted = AccessibilityPermissionService.requestPermissionPrompt()
        scheduleAccessibilityPermissionRefresh()
    }

    var shouldShowInputMonitoringHint: Bool {
        InputMonitoringHintBanner.shouldShow(
            inputMonitoringGranted: inputMonitoringPermissionGranted,
            dismissed: appSettings.hasDismissedInputMonitoringHint
        )
    }

    func dismissInputMonitoringHintPermanently() {
        appSettings.hasDismissedInputMonitoringHint = true
    }

    func requestInputMonitoringPermission() {
        inputMonitoringPermissionGranted = InputMonitoringPermissionService.requestPermissionPrompt()
        InputMonitoringPermissionService.openSystemSettings()
        scheduleAccessibilityPermissionRefresh()
    }

    private func scheduleAccessibilityPermissionRefresh() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.refreshAccessibilityPermission()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            self?.refreshAccessibilityPermission()
        }
    }
}

// MARK: - Notification for Popover Dismissal

extension Notification.Name {
    static let dismissPopover = Notification.Name("dismissPopover")
}
