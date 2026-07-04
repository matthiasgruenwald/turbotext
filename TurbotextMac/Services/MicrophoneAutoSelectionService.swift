import CoreAudio
import Foundation

/// Thin adapter around `MicrophoneFavoritesStore`'s resolution logic: owns the CoreAudio
/// hardware-change listener and the retry-after-delay workaround, resolves the active
/// microphone on each change, and persists the result for `AudioRecorder` to read.
/// Never touches the macOS-wide default input device — purely app-internal (see ADR-0003).
@MainActor
final class MicrophoneAutoSelectionService {
    private static let systemObject = AudioObjectID(kAudioObjectSystemObject)

    private let favoritesStore: MicrophoneFavoritesStore
    private let selectedMicUIDKey: String
    private let deviceProvider: () -> [AudioInputDevice]
    private let defaultDeviceIDProvider: () -> AudioDeviceID?
    private let defaults: PersistenceProvider
    private var listenerBlock: AudioObjectPropertyListenerBlock?

    /// Fired every time `applySelection()` runs, with the freshly resolved microphone,
    /// so UI showing the active microphone can be told to re-render.
    var onSelectionApplied: ((ActiveMicrophone) -> Void)?

    init(
        favoritesStore: MicrophoneFavoritesStore,
        selectedMicUIDKey: String = "selectedMicUID",
        deviceProvider: @escaping () -> [AudioInputDevice] = MicrophoneService.availableInputDevices,
        defaultDeviceIDProvider: @escaping () -> AudioDeviceID? = MicrophoneService.defaultInputDeviceID,
        defaults: PersistenceProvider = UserDefaultsPersistence.shared
    ) {
        self.favoritesStore = favoritesStore
        self.selectedMicUIDKey = selectedMicUIDKey
        self.deviceProvider = deviceProvider
        self.defaultDeviceIDProvider = defaultDeviceIDProvider
        self.defaults = defaults
    }

    func start() {
        applySelection()
        observeDeviceChanges()
    }

    func stop() {
        guard listenerBlock != nil else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        if let listenerBlock {
            AudioObjectRemovePropertyListenerBlock(Self.systemObject, &address, DispatchQueue.main, listenerBlock)
        }
        listenerBlock = nil
    }

    func applySelection() {
        let resolved = favoritesStore.resolveActiveDevice(
            availableDevices: deviceProvider(),
            systemDefaultID: defaultDeviceIDProvider()
        )
        persist(resolved)
        onSelectionApplied?(resolved)
    }

    private func persist(_ resolved: ActiveMicrophone) {
        guard resolved.source == .favorite, let uid = resolved.uid else {
            defaults.removeObject(forKey: selectedMicUIDKey)
            return
        }
        defaults.set(uid, forKey: selectedMicUIDKey)
    }

    private func observeDeviceChanges() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.applySelection()
            }
            // Re-apply after a short delay: newly plugged devices can appear in the
            // device list before their name/UID properties are queryable, so the
            // immediate pass above may miss them.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self?.applySelection()
            }
        }
        listenerBlock = block
        AudioObjectAddPropertyListenerBlock(Self.systemObject, &address, DispatchQueue.main, block)
    }
}
