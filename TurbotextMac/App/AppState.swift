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
    private let settingsState: SettingsState
    let workflowLifecycle: WorkflowLifecycleManager
    let quotaManager: QuotaManager
    let fallbackManager: GroqFallbackManager
    let microphoneState: MicrophoneState
    private let localModelState: LocalModelState

    var activeWorkflow: (any Workflow)? { workflowLifecycle.activeWorkflow }
    var currentPhase: WorkflowPhase { workflowLifecycle.currentPhase }

    var page: PopoverPage = .main {
        didSet {
            guard oldValue != page else { return }
            onCloudIndicatorRefreshNeeded?()
        }
    }
    var isPopoverShown = false
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
    var onPreferredContentSizeChange: ((CGSize) -> Void)?
    var onCloudIndicatorRefreshNeeded: (() -> Void)?
    /// Fired whenever `appSettings` actually changes, so the app layer can wire
    /// settings-change side-effect observers (e.g. `PrewarmObserver`, `DockModeObserver`)
    /// without `AppState` itself orchestrating them.
    var onAppSettingsChanged: ((AppSettings, AppSettings) -> Void)?
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

    init(
        quotaManager: QuotaManager = GroqQuotaManager.shared,
        fallbackManager: GroqFallbackManager = GroqFallbackManager.shared
    ) {
        self.quotaManager = quotaManager
        self.fallbackManager = fallbackManager
        self.cloudTranscriptionRouter = CloudTranscriptionRouter(quotaManager: quotaManager, fallbackManager: fallbackManager)
        let store = ShortcutStore()
        self.shortcutStore = store
        self.hotkeyService = HotkeyService(store: store)
        self.microphoneState = MicrophoneState()
        self.networkPingService = NetworkPingService()
        let settings = SettingsState()
        self.settingsState = settings
        self.localModelState = LocalModelState(
            getSelectedModelName: { settings.appSettings.selectedLocalTranscriptionModelName },
            setSelectedModelName: { settings.appSettings.selectedLocalTranscriptionModelName = $0 },
            getSecureLocalModeEnabled: { settings.appSettings.secureLocalModeEnabled },
            setSecureLocalModeEnabled: { settings.appSettings.secureLocalModeEnabled = $0 },
            getHasAutoSelectedFastLocalModel: { settings.appSettings.hasAutoSelectedFastLocalModel },
            setHasAutoSelectedFastLocalModel: { settings.appSettings.hasAutoSelectedFastLocalModel = $0 }
        )

        let lifecycle = WorkflowLifecycleManager()
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
        lifecycle.orchestrator.onAccessibilityPermissionChange = { [weak self] granted in
            self?.accessibilityPermissionGranted = granted
        }
        lifecycle.onWillPaste = { [weak self] in
            guard self?.isPopoverShown == true else { return }
            NotificationCenter.default.post(name: .dismissPopover, object: nil)
        }

        settingsState.onAppSettingsChanged = { [weak self] oldValue, newValue in
            guard let self else { return }
            self.onCloudIndicatorRefreshNeeded?()
            self.onAppSettingsChanged?(oldValue, newValue)
        }

        refreshAccessibilityPermission()
        autoSelectFastLocalModelIfNeeded()
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
        GroqFallbackBanner.content(
            fallbackActive: fallbackManager.isActive,
            resetAt: fallbackManager.rateLimitResetAt,
            secureLocalModeEnabled: appSettings.secureLocalModeEnabled
        )
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
            groqFallbackActive: fallbackManager.isActive,
            groqQuotaUsedToday: quotaManager.formattedUsedToday
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

    var resolvedLocalModelName: String { localModelState.resolvedLocalModelName }
    var selectedLocalModelDisplayName: String { localModelState.selectedModelDisplayName }
    var selectedLocalModelName: String { localModelState.selectedModelName }
    var selectedLocalModelIsInstalled: Bool { localModelState.selectedModelIsInstalled }
    var isDownloadingLocalModel: Bool { localModelState.isDownloading }
    var localModelDownloadButtonTitle: String { localModelState.downloadButtonTitle }
    var localModelDownloadProgress: Double? { localModelState.downloadProgress }
    var localModelDownloadStatusText: String? { localModelState.downloadStatusText }
    var localModelDownloadErrorText: String? { localModelState.downloadErrorText }

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
            return SpokenRewriteWorkflow.textImprovement(
                settings: textImprovementSettings,
                language: transcriptionSettings.language,
                providerMode: appSettings.rewritingProviderMode,
                transcriber: transcriber(for: .remote)
            )
        case .dampfAblassen:
            return SpokenRewriteWorkflow.dampfAblassen(
                settings: dampfAblassenSettings,
                customTerms: textImprovementSettings.customTerms,
                language: transcriptionSettings.language,
                providerMode: appSettings.rewritingProviderMode,
                transcriber: transcriber(for: .remote)
            )
        case .emojiText:
            return SpokenRewriteWorkflow.emojiText(
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
    }

    func enableSecureLocalMode() {
        appSettings.secureLocalModeEnabled = true
        if !selectedLocalModelIsInstalled {
            installSelectedLocalModel()
        }
    }

    func installSelectedLocalModel() {
        localModelState.installSelectedModel()
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
        localModelState.autoSelectFastModelIfNeeded()
    }

    /// Exposed so `PrewarmObserver` (wired by `AppDelegate`) can trigger prewarm without
    /// `AppState` orchestrating the settings-change side effect itself.
    func prewarmLocalTranscriptionIfNeeded() {
        localModelState.prewarmIfNeeded()
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
