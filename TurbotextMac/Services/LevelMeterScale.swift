import Foundation

/// Scales the input level for the recording meter so quiet microphones still move the bar.
/// The top follows the loudest recent peak; the floor is the usable-signal threshold.
struct LevelMeterScale: Equatable {
    static let floor: Float = AudioRecorder.usableSignalThreshold
    static let minimumTop: Float = -40
    static let releasePerSecond: Float = 10
    static let initial = LevelMeterScale(top: minimumTop)

    let top: Float

    func updated(forPeak peak: Float, elapsed: TimeInterval) -> LevelMeterScale {
        let released = top - Self.releasePerSecond * Float(elapsed)
        return LevelMeterScale(top: min(0, max(Self.minimumTop, max(peak, released))))
    }

    func normalized(_ level: Float) -> Float {
        max(0, min(1, (level - Self.floor) / (top - Self.floor)))
    }
}
