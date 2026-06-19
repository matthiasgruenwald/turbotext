import CoreAudio
import Foundation

/// Watches for audio device changes and keeps `selectedMicUID` (read by `AudioRecorder`)
/// in sync with the highest-priority available favorite from `MicrophoneFavoritesStore`.
/// Never touches the macOS-wide default input device — purely app-internal (see ADR-0003).
@MainActor
final class MicrophoneAutoSelectionService {
    private static let selectedMicUIDKey = "selectedMicUID"
    private static let systemObject = AudioObjectID(kAudioObjectSystemObject)

    private let favoritesStore: MicrophoneFavoritesStore
    private var listenerBlock: AudioObjectPropertyListenerBlock?

    init(favoritesStore: MicrophoneFavoritesStore) {
        self.favoritesStore = favoritesStore
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
        guard !favoritesStore.useSystemDefault else { return }
        let available = MicrophoneService.availableInputDevices()
        guard let selected = favoritesStore.selectedDevice(from: available) else { return }
        UserDefaults.standard.set(selected.uid, forKey: Self.selectedMicUIDKey)
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
        }
        listenerBlock = block
        AudioObjectAddPropertyListenerBlock(Self.systemObject, &address, DispatchQueue.main, block)
    }
}
