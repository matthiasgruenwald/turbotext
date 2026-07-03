import CoreAudio
import Foundation

/// The microphone Turbotext actually uses for app-internal recording, and why.
/// `.favorite` means a favorited device was found among the available devices;
/// `.systemDefault` means no favorite matched (or favorites are disabled), so the
/// macOS default input device is used — app-internally only (see ADR-0003).
struct ActiveMicrophone: Equatable {
    enum Source: Equatable {
        case favorite
        case systemDefault
    }

    let uid: String?
    let source: Source
}

/// Pure decision logic for "which microphone is active?". No I/O, no CoreAudio calls,
/// no persistence — takes the current favorites/availability/default snapshot and
/// returns the resolved microphone. Callers are responsible for applying the result
/// (e.g. persisting `uid` for `AudioRecorder` to read).
enum MicrophoneResolution {
    static func resolve(
        favoriteUIDs: [String],
        useSystemDefault: Bool,
        availableDevices: [AudioInputDevice],
        systemDefaultDeviceID: AudioDeviceID?
    ) -> ActiveMicrophone {
        if !useSystemDefault,
           let favorite = favoriteUIDs.lazy.compactMap({ uid in availableDevices.first { $0.uid == uid } }).first {
            return ActiveMicrophone(uid: favorite.uid, source: .favorite)
        }
        let defaultUID = systemDefaultDeviceID.flatMap { id in availableDevices.first { $0.id == id }?.uid }
        return ActiveMicrophone(uid: defaultUID, source: .systemDefault)
    }
}
