import XCTest
@testable import Turbotext

final class LevelMeterScaleTests: XCTestCase {

    func testSilenceBelowFloorShowsNothing() {
        XCTAssertEqual(LevelMeterScale.initial.normalized(-60), 0)
    }

    func testQuietSpeechFillsMostOfBarOnFreshScale() {
        let level = LevelMeterScale.initial.normalized(-45)
        XCTAssertEqual(level, 9.0 / 14.0, accuracy: 0.001)
    }

    func testTopFollowsLouderPeakImmediately() {
        let scale = quietScale().updated(forPeak: -20, elapsed: 0.05)
        XCTAssertEqual(scale.top, -20)
        XCTAssertEqual(scale.normalized(-20), 1, accuracy: 0.001)
    }

    func testTopReleasesSlowlyButNeverBelowMinimum() {
        var scale = quietScale().updated(forPeak: -20, elapsed: 0.05)
        scale = scale.updated(forPeak: -60, elapsed: 1)
        XCTAssertEqual(scale.top, -30, accuracy: 0.001)
        scale = scale.updated(forPeak: -60, elapsed: 10)
        XCTAssertEqual(scale.top, LevelMeterScale.minimumTop)
    }

    func testNormalizedIsClampedToUnitRange() {
        XCTAssertEqual(LevelMeterScale.initial.normalized(0), 1)
    }

    func testSteadyNoiseShowsNothingAndSpeechStandsOut() {
        var scale = LevelMeterScale.initial
        for _ in 0..<40 { scale = scale.updated(forPeak: -18, elapsed: 0.05) }
        XCTAssertEqual(scale.normalized(-18), 0)
        XCTAssertGreaterThan(scale.normalized(-8), 0.4)
    }

    func testNoiseFloorRisesSlowlyToNewNoiseLevel() throws {
        var scale = LevelMeterScale.initial.updated(forPeak: -50, elapsed: 0.05)
        scale = scale.updated(forPeak: -30, elapsed: 5)
        XCTAssertEqual(try XCTUnwrap(scale.noiseFloor), -45, accuracy: 0.001)
    }

    func testDigitalSilenceDoesNotDragNoiseFloorBelowFloorMargin() throws {
        let scale = LevelMeterScale.initial.updated(forPeak: -160, elapsed: 0.05)
        XCTAssertEqual(try XCTUnwrap(scale.noiseFloor), LevelMeterScale.floor - LevelMeterScale.noiseMargin)
    }

    private func quietScale() -> LevelMeterScale {
        LevelMeterScale.initial.updated(forPeak: -60, elapsed: 0.05)
    }
}
