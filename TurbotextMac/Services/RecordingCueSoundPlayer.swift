import AppKit

/// Short audible cues so the user knows when it's safe to start/stop talking —
/// useful in particular for Bluetooth mics, whose hardware handoff can take a
/// few seconds after the pill already shows "recording".
enum RecordingCueSoundPlayer {
    private static let tickInterval: TimeInterval = 0.12
    // Bluetooth output routes are often idle between cues and need to wake up before
    // audio actually reaches the device — the first ~600ms of scheduled playback gets
    // silently swallowed. Delaying the whole sequence lets the route wake up before
    // any tick is expected to be audible. Other outputs don't have this wake-up lag,
    // so they get no artificial delay.
    private static let bluetoothRouteWarmupDelay: TimeInterval = 0.6
    // NSSound.play() is fire-and-forget: an unretained instance can be deallocated
    // before playback actually starts, silently dropping the sound. Keep a strong
    // reference until it's done, then let it go.
    private static var retainedSounds: [NSSound] = []

    static func playStart(isBluetoothDevice: Bool) {
        playTicks(count: 2, isBluetoothDevice: isBluetoothDevice)
    }

    static func playEnd(isBluetoothDevice: Bool) {
        playTicks(count: 3, isBluetoothDevice: isBluetoothDevice)
    }

    private static func playTicks(count: Int, isBluetoothDevice: Bool) {
        let warmupDelay = isBluetoothDevice ? bluetoothRouteWarmupDelay : 0
        for i in 0..<count {
            let delay = warmupDelay + Double(i) * tickInterval
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard let sound = NSSound(named: "Tink") else { return }
                retainedSounds.append(sound)
                sound.play()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    retainedSounds.removeAll { $0 === sound }
                }
            }
        }
    }
}
