import Foundation

/// Scales the input level for the recording meter so quiet microphones still move the bar
/// and steady background noise does not fill it. The floor follows the lowest recent peak,
/// the top follows the loudest recent peak.
struct LevelMeterScale: Equatable {
    static let floor: Float = AudioRecorder.usableSignalThreshold
    static let noiseMargin: Float = 3
    static let minimumSpan: Float = 10
    static let minimumTop: Float = -40
    static let releasePerSecond: Float = 10
    static let noiseRisePerSecond: Float = 1
    static let initial = LevelMeterScale(top: minimumTop, noiseFloor: nil)

    let top: Float
    let noiseFloor: Float?

    func updated(forPeak peak: Float, elapsed: TimeInterval) -> LevelMeterScale {
        let seconds = Float(elapsed)
        let risen = noiseFloor.map { $0 + Self.noiseRisePerSecond * seconds } ?? peak
        let newNoise = max(Self.floor - Self.noiseMargin, min(peak, risen))
        let released = top - Self.releasePerSecond * seconds
        let newTop = max(Self.minimumTop, newNoise + Self.minimumSpan, peak, released)
        return LevelMeterScale(top: min(0, newTop), noiseFloor: newNoise)
    }

    func normalized(_ level: Float) -> Float {
        let displayFloor = (noiseFloor ?? Self.floor - Self.noiseMargin) + Self.noiseMargin
        return max(0, min(1, (level - displayFloor) / (top - displayFloor)))
    }
}
