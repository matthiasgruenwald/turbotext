import XCTest
@testable import Turbotext

final class NetworkStatusIndicatorTests: XCTestCase {

    func testGreenStatusMapsToGreenColor() {
        XCTAssertEqual(NetworkStatusIndicator.color(for: .green), .green)
    }

    func testYellowStatusMapsToYellowColor() {
        XCTAssertEqual(NetworkStatusIndicator.color(for: .yellow), .yellow)
    }

    func testRedStatusMapsToRedColor() {
        XCTAssertEqual(NetworkStatusIndicator.color(for: .red), .red)
    }

    func testHoverTextFormatsLatencyAndLossRoundedToWholeNumbers() {
        let text = NetworkStatusIndicator.hoverText(averageLatencyMs: 42.4, packetLossPercent: 0)
        XCTAssertEqual(text, "42 ms · 0% Verlust")
    }

    func testHoverTextRoundsLatencyAndLoss() {
        let text = NetworkStatusIndicator.hoverText(averageLatencyMs: 133.6, packetLossPercent: 14.6)
        XCTAssertEqual(text, "134 ms · 15% Verlust")
    }

    func testHoverTextHandlesMissingLatency() {
        let text = NetworkStatusIndicator.hoverText(averageLatencyMs: nil, packetLossPercent: 100)
        XCTAssertEqual(text, "Keine Verbindung")
    }

    func testStatusLabelForGreen() {
        XCTAssertEqual(NetworkStatusIndicator.statusLabel(for: .green), "Online")
    }

    func testStatusLabelForYellow() {
        XCTAssertEqual(NetworkStatusIndicator.statusLabel(for: .yellow), "Eingeschränkte Verbindung")
    }

    func testStatusLabelForRed() {
        XCTAssertEqual(NetworkStatusIndicator.statusLabel(for: .red), "Keine Verbindung")
    }
}
