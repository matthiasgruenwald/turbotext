import Foundation
import XCTest
@testable import Turbotext

final class TranscriptionDeadlineTests: XCTestCase {
    func testDeadlineIsRecordingDurationPlusBufferWithTwentySecondFloor() {
        XCTAssertEqual(TranscriptionDeadline.deadline(for: 0), .seconds(20))
        XCTAssertEqual(TranscriptionDeadline.deadline(for: 2), .seconds(22))
    }

    func testDeadlineGrowsWithRecordingDurationPlusBuffer() {
        XCTAssertEqual(TranscriptionDeadline.deadline(for: 20), .seconds(40))
        XCTAssertEqual(TranscriptionDeadline.deadline(for: 300), .seconds(320))
    }

    func testRunReturnsOperationResultWithinDeadline() async throws {
        let result = try await TranscriptionDeadline.run(within: .seconds(5)) { "fertig" }
        XCTAssertEqual(result, "fertig")
    }

    func testRunForwardsOperationError() async {
        struct EngineError: Error {}
        do {
            _ = try await TranscriptionDeadline.run(within: .seconds(5)) { () async throws -> String in
                throw EngineError()
            }
            XCTFail("expected EngineError to be forwarded")
        } catch {
            XCTAssertTrue(error is EngineError)
        }
    }

    func testRunThrowsExceededWhenOperationOutlivesDeadline() async {
        let started = ContinuousClock.now
        do {
            _ = try await TranscriptionDeadline.run(within: .milliseconds(50)) { () async throws -> String in
                try await Task.sleep(for: .seconds(30))
                return "nie erreicht"
            }
            XCTFail("expected Exceeded to be thrown")
        } catch is TranscriptionDeadline.Exceeded {
            XCTAssertLessThan(started.duration(to: .now), .seconds(5))
        } catch {
            XCTFail("expected Exceeded, got \(error)")
        }
    }

    func testRunThrowsCancellationWhenSurroundingTaskIsCancelled() async {
        let task = Task {
            try await TranscriptionDeadline.run(within: .seconds(30)) { () async throws -> String in
                try await Task.sleep(for: .seconds(30))
                return "nie erreicht"
            }
        }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("expected CancellationError")
        } catch is CancellationError {
        } catch {
            XCTFail("expected CancellationError, got \(error)")
        }
    }

    func testRunReturnsPromptlyEvenWhenLosingOperationIgnoresCancellation() async {
        let started = ContinuousClock.now
        do {
            _ = try await TranscriptionDeadline.run(within: .milliseconds(50)) { () async throws -> String in
                // Simulates a stalled engine whose await never unwinds on cancellation.
                await withUnsafeContinuation { (_: UnsafeContinuation<Void, Never>) in }
                return "nie erreicht"
            }
            XCTFail("expected Exceeded to be thrown")
        } catch is TranscriptionDeadline.Exceeded {
            XCTAssertLessThan(started.duration(to: .now), .seconds(5))
        } catch {
            XCTFail("expected Exceeded, got \(error)")
        }
    }
}
