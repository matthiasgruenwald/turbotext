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
    let orchestrator: WorkflowOrchestrator

    var activeWorkflow: (any Workflow)? {
        orchestrator.activeWorkflow
    }
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
    private var activeLaunchSource: WorkflowLaunchSource = .manual
    private var lastPopoverPasteTarget: PasteTarget?
    private var isCheckingGroqQuota = false
    private let settingsStore: SettingsStore

    // Persisted settings
    var appSettings: AppSettings {
        didSet {
            saveSettings()
            prewarmLocalTranscriptionIfNeeded()
            onCloudIndicatorRefreshNeeded?()
            if oldValue.dockModeEnabled != appSettings.dockModeEnabled {
                DockModeService.apply(dockModeEnabled: appSettings.dockModeEnabled)
            }
        }
    }
    var transcriptionSettings: TranscriptionSettings {
        didSet { saveSettings() }
    }
    var textImprovementSettings: TextImprovementSettings {
        didSet { saveSettings() }
    }
    var dampfAblassenSettings: DampfAblassenSettings {
        didSet { saveSettings() }
    }
    var emojiTextSettings: EmojiTextSettings {
        didSet { saveSettings() }
    }

    // Hotkeys
    let shortcutStore: ShortcutStore
    let hotkeyService: HotkeyService

    // Microphone favorites
    let microphoneFavoritesStore: MicrophoneFavoritesStore
    private let microphoneAutoSelectionService: MicrophoneAutoSelectionService

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

    var currentPhase: WorkflowPhase {
        activeWorkflow?.phase ?? .idle
    }

    func openMicrophoneSettings() {
        requestedSettingsSection = .transcription
        page = .settings
    }

    /// Bumped whenever `MicrophoneAutoSelectionService` re-evaluates the active device,
    /// so views reading `activeMicrophoneDisplayName` get invalidated on hardware changes.
    private(set) var microphoneDeviceSignal = 0

    var activeMicrophoneDisplayName: String {
        _ = microphoneDeviceSignal
        return microphoneFavoritesStore.activeDeviceDisplayName(
            availableDevices: MicrophoneService.availableInputDevices(),
            defaultDeviceID: MicrophoneService.defaultInputDeviceID()
        )
    }

    init() {
        let store = ShortcutStore()
        self.shortcutStore = store
        self.hotkeyService = HotkeyService(store: store)
        let micFavorites = MicrophoneFavoritesStore()
        self.microphoneFavoritesStore = micFavorites
        let micAutoSelection = MicrophoneAutoSelectionService(favoritesStore: micFavorites)
        self.microphoneAutoSelectionService = micAutoSelection
        self.networkPingService = NetworkPingService()
        let settingsStore = SettingsStore()
        self.settingsStore = settingsStore
        let loadedSettings = settingsStore.load()
        self.appSettings = loadedSettings.app
        self.transcriptionSettings = loadedSettings.transcription
        self.textImprovementSettings = loadedSettings.textImprovement
        self.dampfAblassenSettings = loadedSettings.dampfAblassen
        self.emojiTextSettings = loadedSettings.emojiText
        let orchestrator = WorkflowOrchestrator(workflowFactory: { _, _ in nil })
        self.orchestrator = orchestrator
        orchestrator.workflowFactory = { [weak self] type, backendOverride in
            self?.makeWorkflow(type, backendOverride: backendOverride)
        }
        orchestrator.onPasteTargetActivationNeeded = { target in
            target.application.activate(options: [])
        }
        orchestrator.onWorkflowOutput = { [weak self] _ in
            self?.handleWorkflowOutputDelivered()
        }
        orchestrator.onWorkflowFinished = { [weak self] reason in
            self?.handleWorkflowFinished(reason)
        }
        orchestrator.onMenuBarStatusChange = { [weak self] status in
            self?.menuBarStatus = status
        }
        orchestrator.onAccessibilityPermissionChange = { [weak self] granted in
            self?.accessibilityPermissionGranted = granted
        }
        orchestrator.onWillPaste = { [weak self] in
            guard self?.isPopoverShown == true else { return }
            NotificationCenter.default.post(name: .dismissPopover, object: nil)
        }
        refreshAccessibilityPermission()
        autoSelectFastLocalModelIfNeeded()
        prewarmLocalTranscriptionIfNeeded()
        microphoneAutoSelectionService.onSelectionApplied = { [weak self] in
            self?.microphoneDeviceSignal += 1
        }
        microphoneAutoSelectionService.start()
        networkPingService.start()
        checkGroqQuotaIfNeeded()
    }

    func checkGroqQuotaIfNeeded() {
        guard !isCheckingGroqQuota else { return }
        guard let apiKey = KeychainService.load(key: .groqAPIKey) else { return }
        let store = GroqQuotaStore.shared
        guard GroqQuotaCheckScheduler.shouldCheck(
            hasGroqKey: true,
            secureLocalModeEnabled: appSettings.secureLocalModeEnabled,
            remainingAudioSeconds: store.remainingAudioSeconds,
            fallbackActive: store.fallbackActive
        ) else { return }

        isCheckingGroqQuota = true
        Task { @MainActor [weak self] in
            defer { self?.isCheckingGroqQuota = false }
            await TranscriptionService.checkGroqQuotaIfNeeded(apiKey: apiKey)
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
        guard !appSettings.secureLocalModeEnabled, GroqQuotaStore.shared.fallbackActive else { return nil }
        var detail = "OpenAI Whisper aktiv."
        if let resetAt = GroqQuotaStore.shared.rateLimitResetAt {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            detail += " Groq zurück um \(formatter.string(from: resetAt))."
        }
        return (title: "Groq-Kontingent aufgebraucht", detail: detail)
    }

    var onlineKeyHintBannerContent: (title: String, detail: String)? {
        OnlineKeyHintBanner.content(
            secureLocalModeEnabled: appSettings.secureLocalModeEnabled,
            hasAnyAPIKey: KeychainService.load(key: .openAIAPIKey) != nil
                || KeychainService.load(key: .groqAPIKey) != nil
        )
    }

    func workflowSubtitle(for type: WorkflowType) -> String {
        switch type {
        case .transcription:
            if appSettings.secureLocalModeEnabled {
                let modelName = selectedLocalModelName
                return LocalTranscriptionService.isModelInstalled(modelName)
                    ? "Lokal: \(LocalTranscriptionModel.displayName(for: modelName))."
                    : "Lokales WhisperKit-Modell fehlt."
            }
            return "Sprache rein. Landet in Zwischenablage."
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
        guard isWorkflowAvailable(type) else {
            if source == .manual {
                page = .settings
            }
            return
        }

        activeLaunchSource = source
        orchestrator.start(
            type,
            source: source,
            backendOverride: backendOverride,
            pasteTarget: capturePasteTarget(for: source)
        )

        page = source.presentsWorkflowPage ? .workflow : .main
    }

    private func makeWorkflow(
        _ type: WorkflowType,
        backendOverride: TranscriptionBackend?
    ) -> (any Workflow)? {
        switch type {
        case .transcription:
            return TranscriptionWorkflow(
                customTerms: textImprovementSettings.customTerms,
                language: transcriptionSettings.language,
                backend: backendOverride ?? (appSettings.secureLocalModeEnabled ? .local : .remote),
                localModelName: selectedLocalModelName
            )
        case .localTranscription:
            return TranscriptionWorkflow(
                type: .localTranscription,
                customTerms: textImprovementSettings.customTerms,
                language: transcriptionSettings.language,
                backend: .local,
                localModelName: selectedLocalModelName
            )
        case .textImprover:
            return TextImprovementWorkflow(
                settings: textImprovementSettings,
                language: transcriptionSettings.language
            )
        case .dampfAblassen:
            return DampfAblassenWorkflow(
                settings: dampfAblassenSettings,
                customTerms: textImprovementSettings.customTerms,
                language: transcriptionSettings.language
            )
        case .emojiText:
            return EmojiTextWorkflow(
                settings: emojiTextSettings,
                customTerms: textImprovementSettings.customTerms,
                language: transcriptionSettings.language
            )
        }
    }

    func isWorkflowAvailable(_ type: WorkflowType) -> Bool {
        switch type {
        case .localTranscription:
            return selectedLocalModelIsInstalled
        case .transcription:
            return appSettings.secureLocalModeEnabled
                ? selectedLocalModelIsInstalled
                : KeychainService.isConfigured
        case .textImprover, .dampfAblassen, .emojiText:
            return !appSettings.secureLocalModeEnabled && KeychainService.isConfigured
        }
    }

    func stopCurrentWorkflow() {
        orchestrator.stop()
    }

    func resetCurrentWorkflow() {
        orchestrator.reset()
        activeLaunchSource = .manual
        menuBarStatus = .idle
        page = .main
    }

    private func handleWorkflowOutputDelivered() {
        if activeLaunchSource == .hotkeyBackground {
            page = .main
        }
    }

    private func handleWorkflowFinished(_ reason: WorkflowOrchestrator.FinishReason) {
        switch reason {
        case .errorDuringBackgroundLaunch:
            page = .main
        case .outputCleanup:
            activeLaunchSource = .manual
            if !isPopoverShown {
                page = .main
            }
        }
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

// MARK: - Settings Persistence

private extension AppState {
    func saveSettings() {
        settingsStore.save(
            app: appSettings,
            transcription: transcriptionSettings,
            textImprovement: textImprovementSettings,
            dampfAblassen: dampfAblassenSettings,
            emojiText: emojiTextSettings
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
