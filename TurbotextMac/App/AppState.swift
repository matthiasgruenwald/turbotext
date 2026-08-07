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
    private let appleSpeechAvailability: AppleSpeechAvailability
    private let rewriteConsentCoordinator: RewriteConsentCoordinating
    private var workflowFactory: WorkflowFactory!

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

    let permissionGuideCoordinator: PermissionGuideCoordinator

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
    var isAppleSpeechAvailable: Bool { appleSpeechAvailability.readiness.isReady }
    var selectedLocalTranscriptionBackend: LocalTranscriptionBackend {
        get { appSettings.selectedLocalTranscriptionBackend }
        set { appSettings.selectedLocalTranscriptionBackend = newValue }
    }
    var appleSpeechAvailabilityStatus: AppleSpeechAvailabilityStatus { appleSpeechAvailability.status }
    var isInstallingAppleSpeechAssets: Bool { appleSpeechAvailability.isInstallingAssets }
    var appleSpeechAssetInstallationErrorText: String? { appleSpeechAvailability.assetInstallationErrorText }
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
        self.permissionGuideCoordinator = PermissionGuideCoordinator()
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
        self.appleSpeechAvailability = AppleSpeechAvailability()
        self.rewriteConsentCoordinator = rewriteConsentCoordinator ?? RewriteConsentCoordinator(
            getConsents: { settings.appSettings.rewriteConsents },
            setConsents: { settings.appSettings.rewriteConsents = $0 }
        )

        let lifecycle = WorkflowLifecycleManager()
        self.workflowLifecycle = lifecycle
        lifecycle.isPopoverShown = { [weak self] in self?.isPopoverShown ?? false }

        let orchestrator = lifecycle.orchestrator
        self.workflowFactory = WorkflowFactory(
            resolveTranscriber: { [weak self] backendOverride in
                self?.resolvedTranscriber(backendOverride: backendOverride)
                    ?? WorkflowFactory.ResolvedTranscriber(transcriber: Self.deallocatedSelfTranscriber, backend: .local, resolution: .unavailable)
            },
            localTranscriber: { [weak self] in
                self?.transcriber(for: .local) ?? Self.deallocatedSelfTranscriber
            },
            rewriteConsentCoordinator: self.rewriteConsentCoordinator,
            secureAppleSpeechAssetsOnDemand: { [weak self] in self?.secureAppleSpeechAssetsOnDemand() },
            onLiveTranscriptUpdate: { [weak orchestrator] display in
                orchestrator?.updateLiveTranscriptDisplay(display)
            },
            onBergung: { [weak orchestrator] message in
                orchestrator?.reportBergung(message: message)
            },
            rewriteProcessingLabel: { [weak self] in self?.rewriteProcessingLabel() }
        )

        lifecycle.workflowFactory = { [weak self] type, backendOverride in
            guard let self else { return nil }
            return self.workflowFactory.build(type, backendOverride: backendOverride, settings: WorkflowFactory.Settings(
                appSettings: self.appSettings,
                transcriptionSettings: self.transcriptionSettings,
                textImprovementSettings: self.textImprovementSettings,
                dampfAblassenSettings: self.dampfAblassenSettings,
                emojiTextSettings: self.emojiTextSettings
            ))
        }
        lifecycle.startGate = { [weak self] type in
            self?.startRejection(for: type)
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

        permissionGuideCoordinator.onPermissionStatusChanged = { [weak self] in
            self?.refreshAccessibilityPermission()
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
        Task { [appleSpeechAvailability] in await appleSpeechAvailability.ensureAssetsReady() }
    }

    /// Sprachasset-Bereitschaft (#189, vormals Sprachasset-Sicherstellung #178): Kick-off
    /// aus dem Frühcheck der Live-Session, wenn die Diktat-Taste ohne bereite Sprachassets
    /// gedrückt wurde — delegiert an denselben Sicherstellungs-Aufruf wie App-Start/Aufwachen.
    func secureAppleSpeechAssetsOnDemand() {
        Task { [appleSpeechAvailability] in await appleSpeechAvailability.ensureAssetsReady() }
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
            backendOverride: backendOverride,
            pasteTarget: capturePasteTarget(for: source)
        )
    }

    /// Derives whether `type` can start right now from Sprachasset-Bereitschaft and the
    /// access configuration (#190) — wired in as `workflowLifecycle`'s `startGate`. `nil`
    /// means "start it". Fixes F1 from #188: the hotkey path used to veto silently here.
    private func startRejection(for type: WorkflowType) -> WorkflowStartRejection? {
        guard type != .localTranscription else {
            guard !isWorkflowAvailable(type) else { return nil }
            return WorkflowStartRejection(
                reason: "localModelNotInstalled",
                message: "Lokales Modell nicht installiert – in den Einstellungen herunterladen.",
                canRetryImmediately: false
            )
        }

        if wantsAppleSpeechLive {
            if case .notReady(let status, let canInstall) = appleSpeechAvailability.readiness {
                if canInstall {
                    secureAppleSpeechAssetsOnDemand()
                }
                return WorkflowStartRejection(
                    reason: "appleSpeech.\(String(describing: status))",
                    message: AppleSpeechUnavailableHint.refusalText(for: status),
                    canRetryImmediately: canInstall
                )
            }
            return nil
        }

        guard KeychainService.isConfigured else {
            return WorkflowStartRejection(
                reason: "accessNotConfigured",
                message: "Kein API-Schlüssel konfiguriert – in den Einstellungen hinterlegen.",
                canRetryImmediately: false
            )
        }
        return nil
    }

    /// Whether the configured backend wants Apple Speech live dictation regardless of
    /// current asset readiness (#190) — what a start rejection checks readiness against.
    /// Mirrors the `alwaysLocalTranscription`+`.appleSpeech` branch of
    /// `TranscriptionBackendResolver`, which only sees readiness as an input and so can't
    /// distinguish "doesn't want Apple Speech" from "wants it but assets aren't ready".
    private var wantsAppleSpeechLive: Bool {
        guard appSettings.alwaysLocalTranscription, selectedLocalTranscriptionBackend == .appleSpeech else {
            return false
        }
        if #available(macOS 26, *) { return true }
        return false
    }

    /// Predicted processing-label routing for the signal pill (#128): known synchronously
    /// from Apple provider availability and the configured online provider. Handed to
    /// `WorkflowFactory` as a closure so it's evaluated fresh at call time.
    private func rewriteProcessingLabel() -> String {
        RewriteRouter.processingLabel(
            appleProviderAvailable: RewriteRouter.resolveAppleProvider() != nil,
            providerMode: appSettings.rewritingProviderMode,
            hasGroqKey: KeychainService.load(key: .groqAPIKey) != nil
        )
    }

    /// Resolves the transcriber for the four cloud-capable spoken workflows via
    /// `TranscriptionBackendResolver` (#123), replacing the direct
    /// `alwaysLocalTranscription ? .local : .remote` checks that used to live here.
    /// `backendOverride`, when `.local`, is treated as an explicit legacy-WhisperKit
    /// request (rule 4) — the offline auto-fallback (rule 3) is decided independently
    /// from live network state, so it no longer needs to flow through this parameter.
    /// Handed to `WorkflowFactory` (#191) as its "Transcriber-Auflösung" dependency.
    private func resolvedTranscriber(
        backendOverride: TranscriptionBackend?
    ) -> WorkflowFactory.ResolvedTranscriber {
        let resolution = TranscriptionBackendResolver.resolve(
            alwaysLocalTranscription: appSettings.alwaysLocalTranscription,
            selectedLocalBackend: selectedLocalTranscriptionBackend,
            appleSpeechAvailable: appleSpeechAvailability.readiness.isReady,
            isOnline: networkPingService.status != .red,
            autoFallbackToLocalOnOffline: appSettings.autoFallbackToLocalOnOffline,
            legacyWhisperKitRequested: backendOverride == .local,
            whisperKitModelInstalled: selectedLocalModelIsInstalled
        )
        switch resolution {
        case .appleSpeech:
            var appleTranscriber: SpokenWorkflowPipeline.Transcriber?
            if #available(macOS 26, *) {
                appleTranscriber = AppleSpeechTranscriptionService.makeTranscriber(
                    partialTranscriptHandler: { [weak self] text in
                        Task { @MainActor in self?.workflowLifecycle.orchestrator.updatePartialTranscript(text) }
                    }
                )
            }
            return WorkflowFactory.ResolvedTranscriber(transcriber: appleTranscriber ?? unavailableTranscriber, backend: .local, resolution: resolution)
        case .remote:
            return WorkflowFactory.ResolvedTranscriber(transcriber: transcriber(for: .remote), backend: .remote, resolution: resolution)
        case .whisperKit:
            return WorkflowFactory.ResolvedTranscriber(transcriber: transcriber(for: .local), backend: .local, resolution: resolution)
        case .unavailable:
            return WorkflowFactory.ResolvedTranscriber(transcriber: unavailableTranscriber, backend: .local, resolution: resolution)
        }
    }

    private var unavailableTranscriber: SpokenWorkflowPipeline.Transcriber { Self.deallocatedSelfTranscriber }

    /// Shared fallback for the rare case a `WorkflowFactory` dependency closure fires
    /// after `self` has already deallocated — same failure the resolved backend reports
    /// when it's genuinely unavailable, just reused instead of duplicated per call site.
    private static let deallocatedSelfTranscriber: SpokenWorkflowPipeline.Transcriber = { _, _, _, _ in
        throw LocalTranscriptionUnavailableError.selectedBackendUnavailable
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
            case .appleSpeech: return appleSpeechAvailability.readiness.isReady
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
        Task { [appleSpeechAvailability] in await appleSpeechAvailability.ensureAssetsReady() }
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
        // Masked keys are otherwise indistinguishable, and mistaking a simulated run for a
        // configured one wastes debugging time.
        if KeychainService.isSimulatingCredentials {
            return "SIM \u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}"
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

    func startPermissionGuide(requested: Set<PermissionGuideStep>) {
        permissionGuideCoordinator.start(requested: requested)
    }

    func requestAccessibilityPermission() {
        startPermissionGuide(requested: [.accessibility])
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
        startPermissionGuide(requested: [.inputMonitoring])
    }
}

// MARK: - Notification for Popover Dismissal

extension Notification.Name {
    static let dismissPopover = Notification.Name("dismissPopover")
}
