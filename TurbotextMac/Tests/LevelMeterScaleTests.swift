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
        let scale = LevelMeterScale.initial.updated(forPeak: -20, elapsed: 0.05)
        XCTAssertEqual(scale.top, -20)
        XCTAssertEqual(scale.normalized(-20), 1, accuracy: 0.001)
    }

    func testTopReleasesSlowlyButNeverBelowMinimum() {
        var scale = LevelMeterScale.initial.updated(forPeak: -20, elapsed: 0.05)
        scale = scale.updated(forPeak: -60, elapsed: 1)
        XCTAssertEqual(scale.top, -30, accuracy: 0.001)
        scale = scale.updated(forPeak: -60, elapsed: 10)
        XCTAssertEqual(scale.top, LevelMeterScale.minimumTop)
    }

    func testNormalizedIsClampedToUnitRange() {
        XCTAssertEqual(LevelMeterScale.initial.normalized(0), 1)
    }
}
