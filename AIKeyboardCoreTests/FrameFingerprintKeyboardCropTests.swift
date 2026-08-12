import XCTest

@testable import AIKeyboardCore

/// Tests for the keyboard-crop path of `FrameFingerprint`: excluding our own UI
/// from the fingerprint band so the loading shimmer can't invalidate a read.
///
/// All helpers here are specific to the deployed-frame simulation and do not
/// appear in `FrameFingerprintTests`.
final class FrameFingerprintKeyboardCropTests: XCTestCase {

    private let width = 320
    private let height = 640

    /// The bottom fraction of the screen our own keyboard covers.
    private var ownUIFraction: Double {
        Double(Theme.Metrics.totalHeight() / KeyboardGeometry.referenceScreenHeight)
    }

    private var ownUIRows: Range<Int> {
        Int((Double(height) * (1 - ownUIFraction)).rounded())..<height
    }

    private func paint(
        _ pixels: inout [UInt8], rows: Range<Int>, columns: Range<Int>, value: UInt8
    ) {
        for y in rows where y >= 0 && y < height {
            for x in columns where x >= 0 && x < width {
                let offset = (y * width + x) * 4
                pixels[offset] = value
                pixels[offset + 1] = value
                pixels[offset + 2] = value
                pixels[offset + 3] = 255
            }
        }
    }

    /// A simulated deployed frame: host conversation on top, our own keyboard
    /// at the bottom, and a bright band of our own animating chrome at the given
    /// leading edge — a shimmer when this was written, `WorkingProgressBar` now.
    /// What it stands for is the thing this test is about: our own UI moving
    /// inside the fingerprint band.
    private func deployedFrame(newest: Range<Int>, shimmer: Int) -> [UInt8] {
        var pixels = [UInt8](repeating: 128, count: width * height * 4)
        paint(&pixels, rows: newest, columns: 24..<220, value: 255)
        paint(&pixels, rows: ownUIRows, columns: 0..<width, value: 60)
        let line = ownUIRows.lowerBound + 96
        paint(&pixels, rows: line..<(line + 11), columns: shimmer..<(shimmer + 90), value: 210)
        return pixels
    }

    private func deployedIdentity(_ pixels: [UInt8]) throws -> FrameIdentity {
        var intent = CaptureIntent()
        intent.setOwnUIHeightFraction(ownUIFraction)
        let value = pixels.withUnsafeBytes { raw in
            FrameFingerprint.make(
                base: raw.baseAddress!, width: width, height: height, bytesPerRow: width * 4,
                format: .bgra8888, bottomCrop: intent.frameBottomCrop)
        }
        return try XCTUnwrap(value).identity
    }

    private var newestMessage: Range<Int> { (ownUIRows.lowerBound - 20)..<(ownUIRows.lowerBound - 4) }
    private var switchedConversation: Range<Int> {
        (ownUIRows.lowerBound - 34)..<(ownUIRows.lowerBound - 4)
    }

    // MARK: - Our own keyboard

    /// The blocker this crop exists for: our own UI animates a shimmer for the whole
    /// read, and our keyboard is 33% of the band, so with it left in, condition 4
    /// refused the answer to the very tap that paid for it. It was
    /// `AIResultPanel.loading`'s three lines when this was measured; that panel is
    /// deleted and `ActionBanner`'s two lines shimmer in its place, which is the
    /// same hazard in a shorter strip — the crop is what makes either harmless.
    func testOurOwnShimmerDoesNotMoveTheIdentity() throws {
        let early = try deployedIdentity(deployedFrame(newest: newestMessage, shimmer: 30))
        let late = try deployedIdentity(deployedFrame(newest: newestMessage, shimmer: 180))
        XCTAssertEqual(early, late)
    }

    /// Excluding our own keyboard must not make the gate blind: a user who
    /// switches conversation mid-read is still caught.
    func testAConversationSwitchUnderOurOwnShimmerStillMovesTheIdentity() throws {
        let before = try deployedIdentity(deployedFrame(newest: newestMessage, shimmer: 30))
        let after = try deployedIdentity(
            deployedFrame(newest: switchedConversation, shimmer: 180))
        XCTAssertNotEqual(before, after)
    }

    /// The crop is the keyboard's claim about itself, read out of a page another
    /// process writes. A zero claim leaves the band where the corpus measured it;
    /// a claim past `Band.maximumOwnUI` is clamped.
    func testAnOutOfRangeClaimCannotMoveTheBandPastTheMeasuredLimit() {
        XCTAssertEqual(FrameReduction.bottomCrop(ownUI: 0), FrameReduction.Band.bottom)
        XCTAssertEqual(FrameReduction.bottomCrop(ownUI: 0.01), FrameReduction.Band.bottom)
        XCTAssertEqual(FrameReduction.bottomCrop(ownUI: .nan), FrameReduction.Band.bottom)
        XCTAssertEqual(FrameReduction.bottomCrop(ownUI: -1), FrameReduction.Band.bottom)
        XCTAssertEqual(FrameReduction.bottomCrop(ownUI: 0.95), FrameReduction.Band.maximumOwnUI)
        XCTAssertEqual(FrameReduction.bottomCrop(ownUI: ownUIFraction), ownUIFraction)
    }

    private let gateSession = UUID()
    private var gateNow: UInt64 { CaptureClock.nanoseconds(1_000) }

    private func gateStatus(_ identity: FrameIdentity) -> CaptureStatus {
        var status = CaptureStatus()
        status.setSessionID(gateSession)
        status.startedAt = CaptureClock.nanoseconds(900)
        status.heartbeatAt = CaptureClock.nanoseconds(999.5)
        status.lastFrameAt = CaptureClock.nanoseconds(999.8)
        status.currentFrameSampledAt = CaptureClock.nanoseconds(999.8)
        status.currentFrameIdentity = identity
        return status
    }

    private func gateRecord(_ identity: FrameIdentity) -> ScreenReadingRecord {
        ScreenReadingRecord(
            sessionID: gateSession,
            requestSequence: 1,
            frameIdentity: identity,
            capturedAt: CaptureClock.nanoseconds(994),
            readAt: CaptureClock.nanoseconds(999.5),
            provenance: "cloud",
            sender: "Maya",
            message: "מתי אתה מגיע?",
            language: KeyboardLanguage.hebrew.rawValue)
    }

    /// The full read survives our own shimmer at the gate.
    func testTheAnswerToTheTapSurvivesOurOwnShimmerAtTheGate() throws {
        let read = try deployedIdentity(deployedFrame(newest: newestMessage, shimmer: 30))
        let confirming = try deployedIdentity(deployedFrame(newest: newestMessage, shimmer: 180))
        XCTAssertEqual(
            CaptureFreshness.evaluate(
                record: gateRecord(read), status: gateStatus(confirming), now: gateNow),
            .offerable)
    }

    /// A conversation switch during the read is still `.superseded` at the gate,
    /// however busy our own animation was.
    func testAConversationSwitchDuringTheReadIsStillSupersededAtTheGate() throws {
        let read = try deployedIdentity(deployedFrame(newest: newestMessage, shimmer: 30))
        let confirming = try deployedIdentity(
            deployedFrame(newest: switchedConversation, shimmer: 180))
        XCTAssertEqual(
            CaptureFreshness.evaluate(
                record: gateRecord(read), status: gateStatus(confirming), now: gateNow),
            .superseded)
    }
}
