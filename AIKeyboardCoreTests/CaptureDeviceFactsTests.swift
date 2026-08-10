import XCTest

@testable import AIKeyboardCore

/// The block that exists so a phone can answer without a Mac attached. Every
/// number this repo has about ReplayKit is a prediction until one of these is
/// written by a real device, so the plumbing has to be right before the one
/// chance to collect them.
final class CaptureDeviceFactsTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("capture-device-facts-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func liveChannelDirectory() throws -> URL {
        let live = directory.appendingPathComponent("channel", isDirectory: true)
        try FileManager.default.createDirectory(at: live, withIntermediateDirectories: true)
        return live
    }

    func testTheFrameShapeIsRecordedOnceAndNotOverwritten() throws {
        let live = try liveChannelDirectory()
        let writer = try XCTUnwrap(CaptureChannelWriter(directory: live))
        writer.begin()

        writer.recordFrameFormat(width: 1206, height: 2622, pixelFormat: 0x4247_5241)  // 'BGRA'
        let first = try XCTUnwrap(writer.status())
        XCTAssertEqual(first.frameWidth, 1206)
        XCTAssertEqual(first.frameHeight, 2622)
        XCTAssertEqual(first.pixelFormatCode, "BGRA")

        // A second frame must not rewrite it: this is a constant for the
        // session, and restating it would spend a seqlock transaction at 4 Hz.
        writer.recordFrameFormat(width: 9, height: 9, pixelFormat: 1)
        XCTAssertEqual(try XCTUnwrap(writer.status()).frameWidth, 1206)
    }

    /// A dimension too large for the field arrives as "at least 65535" rather
    /// than wrapping into a smaller number that looks plausible.
    func testAnOversizeDimensionClampsRatherThanWraps() throws {
        let live = try liveChannelDirectory()
        let writer = try XCTUnwrap(CaptureChannelWriter(directory: live))
        writer.begin()

        writer.recordFrameFormat(width: 70_000, height: 70_000, pixelFormat: 0)
        XCTAssertEqual(try XCTUnwrap(writer.status()).frameWidth, UInt16.max)
    }

    /// The set matters more than the latest value: a session that only ever
    /// reports `.up` cannot tell us whether the quarter turns are mapped the
    /// right way round, and that is the whole reason `.left`/`.right` is still
    /// documented as a guess.
    func testEveryOrientationSeenIsRemembered() throws {
        let live = try liveChannelDirectory()
        let writer = try XCTUnwrap(CaptureChannelWriter(directory: live))
        writer.begin()

        writer.recordOrientation(.up, raw: 1)
        writer.recordOrientation(.left, raw: 8)

        let status = try XCTUnwrap(writer.status())
        XCTAssertEqual(status.orientationRaw, 8, "the latest is the current one")
        XCTAssertEqual(
            Set(status.orientationsDelivered), [.up, .left],
            "…and the earlier one is not forgotten")
        XCTAssertFalse(status.orientationsDelivered.contains(.down))
    }

    /// Peak, not latest. A spike during a read has to survive being sampled
    /// again a moment later once the memory is back.
    func testTheFootprintKeepsItsPeakAndItsBaseline() throws {
        let live = try liveChannelDirectory()
        let writer = try XCTUnwrap(CaptureChannelWriter(directory: live))
        writer.begin()

        writer.recordFootprint(baselineMB: 8.4, currentMB: 9.1)
        writer.recordFootprint(baselineMB: nil, currentMB: 31.7)
        writer.recordFootprint(baselineMB: nil, currentMB: 10.2)

        let status = try XCTUnwrap(writer.status())
        XCTAssertEqual(status.baselineFootprintMB ?? 0, 8.4, accuracy: 0.05)
        XCTAssertEqual(status.peakFootprintMB ?? 0, 31.7, accuracy: 0.05, "the peak, not the last")

        // The baseline is the process's cost before its first frame, so a later
        // claim about it is not a correction, it is noise.
        writer.recordFootprint(baselineMB: 40, currentMB: nil)
        XCTAssertEqual(try XCTUnwrap(writer.status()).baselineFootprintMB ?? 0, 8.4, accuracy: 0.05)
    }

    func testPauseAndResumeAreCountedSeparatelyAndSaturate() throws {
        let live = try liveChannelDirectory()
        let writer = try XCTUnwrap(CaptureChannelWriter(directory: live))
        writer.begin()

        writer.recordPause(resumed: false)
        writer.recordPause(resumed: true)
        writer.recordPause(resumed: false)

        let status = try XCTUnwrap(writer.status())
        XCTAssertEqual(status.pauseCount, 2)
        XCTAssertEqual(status.resumeCount, 1, "one pause has not come back — which is R11's answer")

        // "Did it come back" is the question, and 255 answers it as well as 300
        // would; a wrap to 0 would answer it wrongly.
        for _ in 0..<300 { writer.recordPause(resumed: true) }
        XCTAssertEqual(try XCTUnwrap(writer.status()).resumeCount, .max)
    }

    /// Nothing has been written yet, and the screen has to say so rather than
    /// show a confident zero. A session that never started reporting "0.0 MB"
    /// reads as a measurement.
    func testAnUnwrittenFactReadsAsAbsentRatherThanZero() throws {
        let live = try liveChannelDirectory()
        let writer = try XCTUnwrap(CaptureChannelWriter(directory: live))
        writer.begin()

        let status = try XCTUnwrap(writer.status())
        XCTAssertNil(status.baselineFootprintMB)
        XCTAssertNil(status.peakFootprintMB)
        XCTAssertNil(status.pixelFormatCode)
        XCTAssertTrue(status.orientationsDelivered.isEmpty)
    }
}
