import CoreAudio
import Foundation

/// Watches for audio device changes and keeps `selectedMicUID` (read by `AudioRecorder`)
/// in sync with the highest-priority available favorite from `MicrophoneFavoritesStore`.
/// Never touches the macOS-wide default input device — purely app-internal (see ADR-0003).
@MainActor
final class MicrophoneAutoSelectionService {
    private static let systemObject = AudioObjectID(kAudioObjectSystemObject)

    private let favoritesStore: MicrophoneFavoritesStore
    private let selectedMicUIDKey: String
    private let deviceProvider: () -> [AudioInputDevice]
    private var listenerBlock: AudioObjectPropertyListenerBlock?

    /// Fired every time `applySelection()` runs, so UI showing the active microphone
    /// (a plain computed property, not itself backed by an @Observable store) can be
    /// told to re-render.
    var onSelectionApplied: (() -> Void)?

    init(
        favoritesStore: MicrophoneFavoritesStore,
        selectedMicUIDKey: String = "selectedMicUID",
        deviceProvider: @escaping () -> [AudioInputDevice] = MicrophoneService.availableInputDevices
    ) {
        self.favoritesStore = favoritesStore
        self.selectedMicUIDKey = selectedMicUIDKey
        self.deviceProvider = deviceProvider
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
        defer { onSelectionApplied?() }
        guard !favoritesStore.useSystemDefault else {
            clearSelectedUID()
            return
        }
        let available = deviceProvider()
        guard let selected = favoritesStore.selectedDevice(from: available) else {
            clearSelectedUID()
            return
        }
        UserDefaults.standard.set(selected.uid, forKey: selectedMicUIDKey)
    }

    private func clearSelectedUID() {
        UserDefaults.standard.removeObject(forKey: selectedMicUIDKey)
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
