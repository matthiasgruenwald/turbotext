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
    let groqTranscriptionProvider: GroqTranscriptionProvider
    let microphoneState: MicrophoneState
    private let localModelState: LocalModelState
    private let appleSpeechAvailabilityState: AppleSpeechAvailabilityState
    private let rewriteConsentCoordinator: RewriteConsentCoordinating

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
    let hotkeyCaptureService: HotkeyCaptureService

    // Network status
    let networkPingService: NetworkPingService

    // Computed
    var isConfigured: Bool {
        KeychainService.isConfigured
            || !LocalTranscriptionService.installedModels().isEmpty
            || isAppleSpeechAvailable
    }

    /// Exposed so `TurbotextMacApp`'s hotkey-time offline-fallback decision
    /// (`TranscriptionFallbackResolver`) can prefer Apple Speech over WhisperKit too (#123).
    var isAppleSpeechAvailable: Bool { appleSpeechAvailabilityState.isAvailable }
    var selectedLocalTranscriptionBackend: LocalTranscriptionBackend {
        get { appSettings.selectedLocalTranscriptionBackend }
        set { appSettings.selectedLocalTranscriptionBackend = newValue }
    }
    var appleSpeechAvailabilityStatus: AppleSpeechAvailabilityStatus { appleSpeechAvailabilityState.status }
    var isInstallingAppleSpeechAssets: Bool { appleSpeechAvailabilityState.isInstallingAssets }
    var appleSpeechAssetInstallationErrorText: String? { appleSpeechAvailabilityState.assetInstallationErrorText }
    var shouldShowOnboarding: Bool {
        !isConfigured && !appSettings.hasSeenOnboarding
    }
    var groqOnboardingState: GroqOnboardingState {
        GroqOnboardingState.resolve(hasGroqKey: KeychainService.load(key: .groqAPIKey) != nil)
    }

    /// Whether a rewrite consent is currently stored for `workflow` (#127), so
    /// `WorkflowsSettingsView` can offer to reset it.
    func hasRewriteConsent(for workflow: WorkflowType) -> Bool {
        rewriteConsentCoordinator.readConsent(workflow) != nil
    }

    /// Clears the stored rewrite consent for `workflow`, requiring a fresh confirmation
    /// the next time an on-device rewrite needs to fall back online (#127).
    func resetRewriteConsent(for workflow: WorkflowType) {
        rewriteConsentCoordinator.writeConsent(workflow, nil)
    }

    func openMicrophoneSettings() {
        requestedSettingsSection = .transcription
        page = .settings
    }

    var activeMicrophoneDisplayName: String {
        microphoneState.activeDeviceDisplayName
    }

    /// Narrow facade for the menu bar status UI — see `MenuBarFacade` for rationale.
    var menuBarFacade: MenuBarFacade {
        MenuBarFacade(
            quotaUIStatus: groqTranscriptionProvider.quotaUIStatus,
            accessibilityPermissionGranted: accessibilityPermissionGranted,
            inputMonitoringPermissionGranted: inputMonitoringPermissionGranted
        )
    }

    init(
        groqTranscriptionProvider: GroqTranscriptionProvider? = nil,
        rewriteConsentCoordinator: RewriteConsentCoordinating? = nil
    ) {
        let groqTranscriptionProvider = groqTranscriptionProvider ?? GroqTranscriptionProvider()
        self.groqTranscriptionProvider = groqTranscriptionProvider
        let store = ShortcutStore()
        self.shortcutStore = store
        self.hotkeyCaptureService = HotkeyCaptureService(store: store)
        self.microphoneState = MicrophoneState()
        self.networkPingService = NetworkPingService()
        let settings = SettingsState()
        self.settingsState = settings
        self.localModelState = LocalModelState(
            getSelectedModelName: { settings.appSettings.selectedLocalTranscriptionModelName },
            setSelectedModelName: { settings.appSettings.selectedLocalTranscriptionModelName = $0 },
            getAlwaysLocalTranscription: { settings.appSettings.alwaysLocalTranscription },
            setAlwaysLocalTranscription: { settings.appSettings.alwaysLocalTranscription = $0 },
            getHasAutoSelectedFastLocalModel: { settings.appSettings.hasAutoSelectedFastLocalModel },
            setHasAutoSelectedFastLocalModel: { settings.appSettings.hasAutoSelectedFastLocalModel = $0 }
        )
        self.appleSpeechAvailabilityState = AppleSpeechAvailabilityState()
        self.rewriteConsentCoordinator = rewriteConsentCoordinator ?? RewriteConsentCoordinator(
            getConsents: { settings.appSettings.rewriteConsents },
            setConsents: { settings.appSettings.rewriteConsents = $0 }
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
        appleSpeechAvailabilityState.refresh()
    }

    func checkGroqQuotaIfNeeded() {
        guard !isCheckingGroqQuota else { return }
        isCheckingGroqQuota = true
        Task { @MainActor [weak self] in
            defer { self?.isCheckingGroqQuota = false }
            guard let self else { return }
            await groqTranscriptionProvider.checkGroqQuotaIfNeeded(
                alwaysLocalTranscription: appSettings.alwaysLocalTranscription
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
        let status = groqTranscriptionProvider.quotaUIStatus
        return GroqFallbackBanner.content(
            fallbackActive: status.fallbackActive,
            resetAt: status.rateLimitResetAt,
            alwaysLocalTranscription: appSettings.alwaysLocalTranscription
        )
    }

    var onlineKeyHintBannerContent: (title: String, detail: String)? {
        OnlineKeyHintBanner.content(
            alwaysLocalTranscription: appSettings.alwaysLocalTranscription,
            hasAnyAPIKey: KeychainService.load(key: .openAIAPIKey) != nil
                || KeychainService.load(key: .groqAPIKey) != nil
        )
    }

    func installAppleSpeechAssets() {
        appleSpeechAvailabilityState.installAssets()
    }

    var transcriptionModeStatus: TranscriptionModeStatus {
        let status = groqTranscriptionProvider.quotaUIStatus
        return TranscriptionModeStatus(
            alwaysLocalTranscription: appSettings.alwaysLocalTranscription,
            selectedLocalBackend: selectedLocalTranscriptionBackend,
            appleSpeechAvailable: isAppleSpeechAvailable,
            selectedLocalModelInstalled: selectedLocalModelIsInstalled,
            selectedLocalModelDisplayName: selectedLocalModelDisplayName,
            isDownloadingLocalModel: isDownloadingLocalModel,
            localModelDownloadStatusText: localModelDownloadStatusText,
            hasGroqKey: KeychainService.load(key: .groqAPIKey) != nil,
            groqFallbackActive: status.fallbackActive,
            groqQuotaUsedToday: status.formattedUsedToday,
            isOnline: networkPingService.status != .red,
            autoFallbackToLocalOnOffline: appSettings.autoFallbackToLocalOnOffline
        )
    }

    func workflowSubtitle(for type: WorkflowType) -> String {
        switch type {
        case .transcription:
            return transcriptionModeStatus.transcriptionWorkflowSubtitle
        case .localTranscription:
            return "Nur lokal. Kein Server."
        case .textImprover, .dampfAblassen, .emojiText:
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
            let resolved = resolvedTranscriber(backendOverride: backendOverride)
            return TranscriptionWorkflow(
                customTerms: textImprovementSettings.customTerms,
                language: transcriptionSettings.language,
                backend: resolved.backend,
                transcriber: resolved.transcriber
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
                transcriber: defaultResolvedTranscriber,
                processingLabelResolver: { [weak self] in self?.rewriteProcessingLabel() },
                improver: { [rewriteConsentCoordinator] text, settings, providerMode in
                    try await LLMService.improveLocalFirst(
                        text: text,
                        settings: settings,
                        providerMode: providerMode,
                        consent: rewriteConsentCoordinator
                    )
                }
            )
        case .dampfAblassen:
            return SpokenRewriteWorkflow.dampfAblassen(
                settings: dampfAblassenSettings,
                customTerms: textImprovementSettings.customTerms,
                language: transcriptionSettings.language,
                providerMode: appSettings.rewritingProviderMode,
                transcriber: defaultResolvedTranscriber,
                processingLabelResolver: { [weak self] in self?.rewriteProcessingLabel() },
                rewriter: { [rewriteConsentCoordinator] text, settings, providerMode in
                    try await LLMService.dampfAblassenLocalFirst(
                        text: text,
                        systemPrompt: settings.systemPrompt,
                        providerMode: providerMode,
                        consent: rewriteConsentCoordinator
                    )
                }
            )
        case .emojiText:
            return SpokenRewriteWorkflow.emojiText(
                settings: emojiTextSettings,
                customTerms: textImprovementSettings.customTerms,
                language: transcriptionSettings.language,
                providerMode: appSettings.rewritingProviderMode,
                transcriber: defaultResolvedTranscriber,
                processingLabelResolver: { [weak self] in self?.rewriteProcessingLabel() },
                rewriter: { [rewriteConsentCoordinator] text, settings, providerMode in
                    try await LLMService.addEmojisLocalFirst(
                        text: text,
                        settings: settings,
                        providerMode: providerMode,
                        consent: rewriteConsentCoordinator
                    )
                }
            )
        }
    }

    /// Predicted processing-label routing for the signal pill (#128): known synchronously
    /// from Apple provider availability and the configured online provider.
    private func rewriteProcessingLabel() -> String {
        RewriteRouter.processingLabel(
            appleProviderAvailable: RewriteRouter.resolveAppleProvider() != nil,
            providerMode: appSettings.rewritingProviderMode,
            hasGroqKey: KeychainService.load(key: .groqAPIKey) != nil
        )
    }

    /// The resolved transcriber for the three rewrite workflows, which never carry a
    /// `backendOverride` — only the `.transcription` factory closure does (from the
    /// hotkey-time offline-fallback decision).
    private var defaultResolvedTranscriber: SpokenWorkflowPipeline.Transcriber {
        resolvedTranscriber(backendOverride: nil).transcriber
    }

    /// Resolves the transcriber for the four cloud-capable spoken workflows via
    /// `TranscriptionBackendResolver` (#123), replacing the direct
    /// `alwaysLocalTranscription ? .local : .remote` checks that used to live here.
    /// `backendOverride`, when `.local`, is treated as an explicit legacy-WhisperKit
    /// request (rule 4) — the offline auto-fallback (rule 3) is decided independently
    /// from live network state, so it no longer needs to flow through this parameter.
    private func resolvedTranscriber(
        backendOverride: TranscriptionBackend?
    ) -> (transcriber: SpokenWorkflowPipeline.Transcriber, backend: TranscriptionBackend) {
        let resolution = TranscriptionBackendResolver.resolve(
            alwaysLocalTranscription: appSettings.alwaysLocalTranscription,
            selectedLocalBackend: selectedLocalTranscriptionBackend,
            appleSpeechAvailable: appleSpeechAvailabilityState.isAvailable,
            isOnline: networkPingService.status != .red,
            autoFallbackToLocalOnOffline: appSettings.autoFallbackToLocalOnOffline,
            legacyWhisperKitRequested: backendOverride == .local,
            whisperKitModelInstalled: selectedLocalModelIsInstalled
        )
        switch resolution {
        case .appleSpeech:
            let appleTranscriber = AppleSpeechAvailability.makeTranscriber(
                partialTranscriptHandler: { [weak self] text in
                    Task { @MainActor in self?.workflowLifecycle.orchestrator.updatePartialTranscript(text) }
                }
            )
            return (appleTranscriber ?? unavailableTranscriber, .local)
        case .remote:
            return (transcriber(for: .remote), .remote)
        case .whisperKit:
            return (transcriber(for: .local), .local)
        case .unavailable:
            return (unavailableTranscriber, .local)
        }
    }

    private var unavailableTranscriber: SpokenWorkflowPipeline.Transcriber {
        { _, _, _, _ in
            throw LocalTranscriptionUnavailableError.selectedBackendUnavailable
        }
    }

    private func transcriber(for backend: TranscriptionBackend) -> SpokenWorkflowPipeline.Transcriber {
        switch backend {
        case .remote:
            return { [groqTranscriptionProvider] audioURL, duration, terms, language in
                try await groqTranscriptionProvider.transcribe(
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
            guard transcriptionModeStatus.alwaysLocalTranscription else {
                return KeychainService.isConfigured
            }
            switch selectedLocalTranscriptionBackend {
            case .appleSpeech: return appleSpeechAvailabilityState.isAvailable
            case .whisperKit: return transcriptionModeStatus.selectedLocalModelInstalled
            }
        case .textImprover, .dampfAblassen, .emojiText:
            return KeychainService.isConfigured
        }
    }

    func stopCurrentWorkflow() {
        workflowLifecycle.stop()
    }

    func resetCurrentWorkflow() {
        workflowLifecycle.reset()
    }

    func enableAlwaysLocalTranscription() {
        appSettings.alwaysLocalTranscription = true
        appleSpeechAvailabilityState.refresh()
        if selectedLocalTranscriptionBackend == .whisperKit, !selectedLocalModelIsInstalled {
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
