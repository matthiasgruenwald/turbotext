import Foundation
import Observation

// MARK: - Ping Outcome

enum PingOutcome: Equatable {
    case success(latencyMs: Double)
    case failure
}

// MARK: - Output Parsing

enum NetworkPingOutputParser {
    private static let roundTripRegex = try! NSRegularExpression(
        pattern: #"round-trip min/avg/max/stddev = ([\d.]+)/([\d.]+)/([\d.]+)/\S+ ms"#
    )

    static func parse(_ output: String) -> PingOutcome {
        let range = NSRange(output.startIndex..<output.endIndex, in: output)
        guard let match = roundTripRegex.firstMatch(in: output, range: range),
              let avgRange = Range(match.range(at: 2), in: output),
              let avgLatencyMs = Double(output[avgRange]) else {
            return .failure
        }
        return .success(latencyMs: avgLatencyMs)
    }
}

// MARK: - Status

enum NetworkQualityStatus: Equatable {
    case green
    case yellow
    case red
}

enum NetworkQualityCalculator {
    private static let yellowLossThresholdPercent = 15.0
    private static let redLossThresholdPercent = 30.0
    private static let greenLatencyThresholdMs = 150.0
    private static let redLatencyThresholdMs = 500.0

    static func status(for outcomes: [PingOutcome]) -> NetworkQualityStatus {
        guard !outcomes.isEmpty else { return .red }

        if hasTwoConsecutiveLowLatencySuccesses(outcomes) {
            return .green
        }

        let lossPercent = packetLossPercent(for: outcomes)
        guard let avgLatencyMs = averageLatencyMs(for: outcomes) else {
            return .red
        }

        if lossPercent > redLossThresholdPercent || avgLatencyMs > redLatencyThresholdMs {
            return .red
        }

        if lossPercent >= yellowLossThresholdPercent || avgLatencyMs >= greenLatencyThresholdMs {
            return .yellow
        }

        return .green
    }

    private static func hasTwoConsecutiveLowLatencySuccesses(_ outcomes: [PingOutcome]) -> Bool {
        guard outcomes.count >= 2 else { return false }
        return outcomes.suffix(2).allSatisfy { outcome in
            guard case .success(let latencyMs) = outcome else { return false }
            return latencyMs < greenLatencyThresholdMs
        }
    }

    static func averageLatencyMs(for outcomes: [PingOutcome]) -> Double? {
        let latencies = outcomes.compactMap { outcome -> Double? in
            guard case .success(let latencyMs) = outcome else { return nil }
            return latencyMs
        }
        guard !latencies.isEmpty else { return nil }
        return latencies.reduce(0, +) / Double(latencies.count)
    }

    static func packetLossPercent(for outcomes: [PingOutcome]) -> Double {
        guard !outcomes.isEmpty else { return 0 }
        let failureCount = outcomes.filter { $0 == .failure }.count
        return Double(failureCount) / Double(outcomes.count) * 100
    }
}

// MARK: - Rolling Window

struct NetworkPingRollingWindow {
    private(set) var outcomes: [PingOutcome] = []
    let maxSize: Int

    init(maxSize: Int) {
        self.maxSize = maxSize
    }

    mutating func record(_ outcome: PingOutcome) {
        outcomes.append(outcome)
        if outcomes.count > maxSize {
            outcomes.removeFirst(outcomes.count - maxSize)
        }
    }
}

// MARK: - Service

@Observable
@MainActor
final class NetworkPingService {
    private static let pingIntervalSeconds: TimeInterval = 3
    private static let rollingWindowSize = 10
    private static let defaultHost = "1.1.1.1"
    private static let pingExecutablePath = "/sbin/ping"

    private(set) var status: NetworkQualityStatus = .red
    private(set) var averageLatencyMs: Double?
    private(set) var packetLossPercent: Double = 0

    var onStatusChanged: ((NetworkQualityStatus) -> Void)?

    private let host: String
    private var window: NetworkPingRollingWindow
    private var timer: Timer?

    init(host: String = NetworkPingService.defaultHost) {
        self.host = host
        self.window = NetworkPingRollingWindow(maxSize: Self.rollingWindowSize)
    }

    func start() {
        guard timer == nil else { return }
        runPingCycle()
        timer = Timer.scheduledTimer(withTimeInterval: Self.pingIntervalSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.runPingCycle()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func runPingCycle() {
        Task { @MainActor in
            let outcome = await Self.executePing(host: host)
            window.record(outcome)
            updatePublishedState()
        }
    }

    private func updatePublishedState() {
        let newStatus = NetworkQualityCalculator.status(for: window.outcomes)
        let statusChanged = newStatus != status
        status = newStatus
        averageLatencyMs = NetworkQualityCalculator.averageLatencyMs(for: window.outcomes)
        packetLossPercent = NetworkQualityCalculator.packetLossPercent(for: window.outcomes)
        if statusChanged {
            onStatusChanged?(newStatus)
        }
    }

    private static func executePing(host: String) async -> PingOutcome {
        await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: pingExecutablePath)
            process.arguments = ["-c", "1", "-t", "1", host]

            let outputPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = Pipe()

            do {
                try process.run()
            } catch {
                return .failure
            }

            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            guard let output = String(data: outputData, encoding: .utf8) else {
                return .failure
            }
            return NetworkPingOutputParser.parse(output)
        }.value
    }
}
