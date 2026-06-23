import XCTest
@testable import Turbotext

// MARK: - Output Parsing

final class NetworkPingOutputParserTests: XCTestCase {

    func testParsesSuccessfulPingLatency() {
        let output = """
        PING 1.1.1.1 (1.1.1.1): 56 data bytes
        64 bytes from 1.1.1.1: icmp_seq=0 ttl=59 time=33.616 ms

        --- 1.1.1.1 ping statistics ---
        1 packets transmitted, 1 packets received, 0.0% packet loss
        round-trip min/avg/max/stddev = 33.616/33.616/33.616/0.000 ms
        """

        let outcome = NetworkPingOutputParser.parse(output)

        guard case .success(let latencyMs) = outcome else {
            return XCTFail("Expected success outcome, got \(outcome)")
        }
        XCTAssertEqual(latencyMs, 33.616, accuracy: 0.001)
    }

    func testParsesSuccessfulPingWithNanStddev() {
        // macOS ping -c 1 has no variance to compute and randomly prints "nan"
        // instead of "0.000" for stddev depending on OS version/run.
        let output = """
        PING 1.1.1.1 (1.1.1.1): 56 data bytes
        64 bytes from 1.1.1.1: icmp_seq=0 ttl=59 time=10.938 ms

        --- 1.1.1.1 ping statistics ---
        1 packets transmitted, 1 packets received, 0.0% packet loss
        round-trip min/avg/max/stddev = 10.938/10.938/10.938/nan ms
        """

        let outcome = NetworkPingOutputParser.parse(output)

        guard case .success(let latencyMs) = outcome else {
            return XCTFail("Expected success outcome, got \(outcome)")
        }
        XCTAssertEqual(latencyMs, 10.938, accuracy: 0.001)
    }

    func testParsesUnreachableHostAsFailure() {
        let output = """
        PING 192.0.2.1 (192.0.2.1): 56 data bytes
        36 bytes from 192.0.2.1: Destination Net Unreachable

        --- 192.0.2.1 ping statistics ---
        1 packets transmitted, 0 packets received, 100.0% packet loss
        """

        let outcome = NetworkPingOutputParser.parse(output)

        XCTAssertEqual(outcome, .failure)
    }

    func testParsesEmptyOutputAsFailure() {
        XCTAssertEqual(NetworkPingOutputParser.parse(""), .failure)
    }

    func testParsesGarbageOutputAsFailure() {
        XCTAssertEqual(NetworkPingOutputParser.parse("not a ping output at all"), .failure)
    }

    func testParsesMissingRoundTripLineAsFailureEvenWithZeroLoss() {
        let output = """
        PING 1.1.1.1 (1.1.1.1): 56 data bytes

        --- 1.1.1.1 ping statistics ---
        1 packets transmitted, 1 packets received, 0.0% packet loss
        """

        XCTAssertEqual(NetworkPingOutputParser.parse(output), .failure)
    }
}

// MARK: - Status Calculation

final class NetworkQualityCalculatorTests: XCTestCase {

    func testEmptyWindowIsRed() {
        let status = NetworkQualityCalculator.status(for: [])
        XCTAssertEqual(status, .red)
    }

    func testAllSuccessfulLowLatencyIsGreen() {
        let outcomes: [PingOutcome] = Array(repeating: .success(latencyMs: 40), count: 10)
        XCTAssertEqual(NetworkQualityCalculator.status(for: outcomes), .green)
    }

    func testZeroLossButBorderlineLatencyJustBelowThresholdIsGreen() {
        let outcomes: [PingOutcome] = Array(repeating: .success(latencyMs: 149.9), count: 10)
        XCTAssertEqual(NetworkQualityCalculator.status(for: outcomes), .green)
    }

    func testZeroLossAtExactly150msIsYellow() {
        let outcomes: [PingOutcome] = Array(repeating: .success(latencyMs: 150), count: 10)
        XCTAssertEqual(NetworkQualityCalculator.status(for: outcomes), .yellow)
    }

    func testZeroLossModerateLatencyIsYellow() {
        let outcomes: [PingOutcome] = Array(repeating: .success(latencyMs: 300), count: 10)
        XCTAssertEqual(NetworkQualityCalculator.status(for: outcomes), .yellow)
    }

    func testFifteenPercentLossIsYellow() {
        var outcomes: [PingOutcome] = Array(repeating: .success(latencyMs: 40), count: 8)
        outcomes.append(.failure)
        outcomes.append(.failure)
        XCTAssertEqual(outcomes.count, 10)
        XCTAssertEqual(NetworkQualityCalculator.status(for: outcomes), .yellow)
    }

    func testJustBelowFifteenPercentLossWithLowLatencyIsGreen() {
        // 1/10 = 10% loss, below the 15% yellow threshold.
        var outcomes: [PingOutcome] = Array(repeating: .success(latencyMs: 40), count: 9)
        outcomes.append(.failure)
        XCTAssertEqual(NetworkQualityCalculator.status(for: outcomes), .green)
    }

    func testOverThirtyPercentLossIsRed() {
        var outcomes: [PingOutcome] = Array(repeating: .success(latencyMs: 40), count: 6)
        outcomes.append(contentsOf: Array(repeating: PingOutcome.failure, count: 4))
        XCTAssertEqual(outcomes.count, 10)
        // 40% loss > 30% threshold
        XCTAssertEqual(NetworkQualityCalculator.status(for: outcomes), .red)
    }

    func testExactlyThirtyPercentLossIsYellowNotRed() {
        var outcomes: [PingOutcome] = Array(repeating: .success(latencyMs: 40), count: 7)
        outcomes.append(contentsOf: Array(repeating: PingOutcome.failure, count: 3))
        XCTAssertEqual(outcomes.count, 10)
        // 30% loss is not > 30%, so should be yellow (>= 15%)
        XCTAssertEqual(NetworkQualityCalculator.status(for: outcomes), .yellow)
    }

    func testAllFailuresIsRed() {
        let outcomes: [PingOutcome] = Array(repeating: .failure, count: 10)
        XCTAssertEqual(NetworkQualityCalculator.status(for: outcomes), .red)
    }

    func testWindowAllRedThenTwoConsecutiveSuccessesIsGreen() {
        var outcomes: [PingOutcome] = Array(repeating: .failure, count: 10)
        outcomes.append(.success(latencyMs: 40))
        outcomes.append(.success(latencyMs: 40))
        XCTAssertEqual(NetworkQualityCalculator.status(for: outcomes), .green)
    }

    func testWindowAllRedThenOnlyOneSuccessIsNotYetGreen() {
        var outcomes: [PingOutcome] = Array(repeating: .failure, count: 10)
        outcomes.append(.success(latencyMs: 40))
        XCTAssertEqual(NetworkQualityCalculator.status(for: outcomes), .red)
    }

    func testHighLatencyAboveFiveHundredMsIsRed() {
        let outcomes: [PingOutcome] = Array(repeating: .success(latencyMs: 600), count: 10)
        XCTAssertEqual(NetworkQualityCalculator.status(for: outcomes), .red)
    }

    func testAverageLatencyIgnoresFailures() {
        let outcomes: [PingOutcome] = [
            .success(latencyMs: 100),
            .success(latencyMs: 200),
            .failure,
        ]
        let averageLatencyMs = NetworkQualityCalculator.averageLatencyMs(for: outcomes)
        XCTAssertEqual(averageLatencyMs ?? .nan, 150, accuracy: 0.001)
    }

    func testAverageLatencyIsNilWhenAllFailed() {
        let outcomes: [PingOutcome] = [.failure, .failure]
        XCTAssertNil(NetworkQualityCalculator.averageLatencyMs(for: outcomes))
    }

    func testAverageLatencyIsNilForEmptyWindow() {
        XCTAssertNil(NetworkQualityCalculator.averageLatencyMs(for: []))
    }

    func testPacketLossPercentComputesCorrectly() {
        let outcomes: [PingOutcome] = [
            .success(latencyMs: 10),
            .failure,
            .failure,
            .success(latencyMs: 10),
        ]
        XCTAssertEqual(NetworkQualityCalculator.packetLossPercent(for: outcomes), 50, accuracy: 0.001)
    }

    func testPacketLossPercentIsZeroForEmptyWindow() {
        XCTAssertEqual(NetworkQualityCalculator.packetLossPercent(for: []), 0, accuracy: 0.001)
    }
}

// MARK: - Rolling Window

final class NetworkPingRollingWindowTests: XCTestCase {

    func testWindowCapsAtMaxSize() {
        var window = NetworkPingRollingWindow(maxSize: 10)
        for index in 0..<15 {
            window.record(.success(latencyMs: Double(index)))
        }
        XCTAssertEqual(window.outcomes.count, 10)
    }

    func testWindowKeepsMostRecentEntries() {
        var window = NetworkPingRollingWindow(maxSize: 3)
        window.record(.success(latencyMs: 1))
        window.record(.success(latencyMs: 2))
        window.record(.success(latencyMs: 3))
        window.record(.success(latencyMs: 4))

        XCTAssertEqual(window.outcomes, [
            .success(latencyMs: 2),
            .success(latencyMs: 3),
            .success(latencyMs: 4),
        ])
    }

    func testEmptyWindowHasNoOutcomes() {
        let window = NetworkPingRollingWindow(maxSize: 10)
        XCTAssertTrue(window.outcomes.isEmpty)
    }
}
