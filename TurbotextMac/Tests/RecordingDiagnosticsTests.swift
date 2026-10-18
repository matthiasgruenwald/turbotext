import XCTest
import AVFoundation
@testable import Turbotext

final class RecordingDiagnosticsTests: XCTestCase {

    private func format(_ rate: Double, _ channels: AVAudioChannelCount = 1) -> AVAudioFormat {
        AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: channels, interleaved: false)!
    }

    private func buffer(_ format: AVAudioFormat, frames: AVAudioFrameCount, value: Float) -> AVAudioPCMBuffer {
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for channel in 0..<Int(format.channelCount) {
            for i in 0..<Int(frames) { buffer.floatChannelData![channel][i] = value }
        }
        return buffer
    }

    func testVerdictRedWithoutBuffers() {
        let diagnostics = RecordingDiagnostics(requestedDeviceUID: nil, targetDeviceID: nil, startFormat: format(48000))
        XCTAssertTrue(diagnostics.verdict.hasPrefix("RED"))
    }

    func testVerdictRedWhenSilent() {
        var diagnostics = RecordingDiagnostics(requestedDeviceUID: nil, targetDeviceID: nil, startFormat: format(48000))
        diagnostics.recordBuffer(format: format(48000), peakLevel: -160, converted: false)
        XCTAssertTrue(diagnostics.verdict.hasPrefix("RED"))
    }

    func testVerdictRedOnWriteFailure() {
        var diagnostics = RecordingDiagnostics(requestedDeviceUID: nil, targetDeviceID: nil, startFormat: format(48000))
        diagnostics.recordBuffer(format: format(48000), peakLevel: -10, converted: false)
        diagnostics.recordWriteFailure()
        XCTAssertTrue(diagnostics.verdict.hasPrefix("RED"))
    }

    func testVerdictGreenAndRecordsFormatSwitch() {
        var diagnostics = RecordingDiagnostics(requestedDeviceUID: "bt", targetDeviceID: 5, startFormat: format(48000))
        diagnostics.recordBuffer(format: format(48000), peakLevel: -30, converted: false)
        diagnostics.recordBuffer(format: format(16000), peakLevel: -20, converted: true)
        XCTAssertEqual(diagnostics.verdict, "GREEN")
        XCTAssertEqual(diagnostics.formatsSeen.count, 2)
        XCTAssertEqual(diagnostics.convertedBuffers, 1)
    }

    func testAdapterPassesMatchingBufferThrough() {
        let target = format(48000)
        let result = BufferFormatAdapter(targetFormat: target).adapt(buffer(target, frames: 480, value: 0.5))
        XCTAssertEqual(result?.converted, false)
    }

    func testAdapterConvertsChangedSampleRateToTargetFormat() throws {
        let target = format(48000)
        let result = try XCTUnwrap(BufferFormatAdapter(targetFormat: target).adapt(buffer(format(16000), frames: 1600, value: 0.5)))
        XCTAssertTrue(result.converted)
        XCTAssertEqual(result.buffer.format, target)
        XCTAssertGreaterThan(result.buffer.frameLength, 3000)
    }
}

extension RecordingDiagnosticsTests {
    func testVerdictRedOnConversionFailureAndSummaryHasActualDevice() {
        let f = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48000, channels: 1, interleaved: false)!
        var diagnostics = RecordingDiagnostics(requestedDeviceUID: "x", targetDeviceID: 1, startFormat: f)
        diagnostics.recordBuffer(format: f, peakLevel: -10, rmsLevel: -20, converted: false)
        diagnostics.recordActualDevice(42)
        diagnostics.recordConversionFailure()
        XCTAssertTrue(diagnostics.verdict.hasPrefix("RED"))
        XCTAssertTrue(diagnostics.summary.contains("actualId=42"))
    }
}
