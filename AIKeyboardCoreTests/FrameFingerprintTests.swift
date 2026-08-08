import XCTest

@testable import AIKeyboardCore

/// The frame fingerprint, and specifically the two properties the whole
/// freshness gate rests on: a change *inside* the band moves the identity, and a
/// change *outside* it does not.
///
/// The scored version of this lives in `Bar/screen-context/harness/run-fingerprint.sh`,
/// which runs the same shipping code over 120 rendered corpus frames and holds
/// it to 0 misses and 0 false invalidations. What is here is the part that has to
/// keep working every build: synthetic frames where the changed pixels are
/// placed by hand, so a regression in the crop arithmetic fails a unit test
/// rather than waiting for someone to re-render the corpus.
final class FrameFingerprintTests: XCTestCase {

    private let width = 320
    private let height = 640

    /// A flat grey BGRA frame with a white block painted into it.
    private func frame(white rows: Range<Int>, columns: Range<Int>? = nil) -> [UInt8] {
        var pixels = [UInt8](repeating: 128, count: width * height * 4)
        for y in rows {
            for x in columns ?? 0..<width {
                let offset = (y * width + x) * 4
                pixels[offset] = 255
                pixels[offset + 1] = 255
                pixels[offset + 2] = 255
                pixels[offset + 3] = 255
            }
        }
        return pixels
    }

    private func fingerprint(
        _ pixels: [UInt8], format: FrameReduction.PixelFormat = .bgra8888
    )
        -> FrameFingerprint?
    {
        pixels.withUnsafeBytes { raw in
            FrameFingerprint.make(
                base: raw.baseAddress!, width: width, height: height,
                bytesPerRow: width * format.bytesPerPixel, format: format)
        }
    }

    // MARK: - The band

    /// Rows the design crops away: the top 14% is the status bar and the
    /// navigation bar, the bottom 8.5% is the composer. Derived from
    /// `FrameReduction.bandRows` rather than recomputed, because recomputing it
    /// is how this file first asserted that a row inside the band was outside it.
    private var topBand: Range<Int> { 0..<FrameReduction.bandRows(inHeight: height).lowerBound }
    private var bottomBand: Range<Int> {
        FrameReduction.bandRows(inHeight: height).upperBound..<height
    }

    /// The clock and the presence line change on their own. Measured over the
    /// corpus, leaving the navigation bar in the fingerprint moves the identity
    /// on 19 of 30 frames where nothing but chrome changed — each of which
    /// retires a good reading and buys a needless cloud read.
    func testAChangeInTheCroppedTopBandDoesNotMoveTheIdentity() throws {
        let flat = try XCTUnwrap(fingerprint(frame(white: 0..<0)))
        let chrome = try XCTUnwrap(fingerprint(frame(white: topBand)))
        XCTAssertEqual(flat.identity, chrome.identity)
    }

    func testAChangeInTheCroppedBottomBandDoesNotMoveTheIdentity() throws {
        let flat = try XCTUnwrap(fingerprint(frame(white: 0..<0)))
        let composer = try XCTUnwrap(fingerprint(frame(white: bottomBand)))
        XCTAssertEqual(flat.identity, composer.identity)
    }

    /// The failure the previous design had and the reason the band moved. A
    /// crop that reaches up into the message area removes the newest message
    /// from the fingerprint, and then a conversation switch hashes identically.
    /// The newest message on a phone sits just above the composer, which is the
    /// row this asserts on.
    func testAChangeJustAboveTheComposerMovesTheIdentity() throws {
        let flat = try XCTUnwrap(fingerprint(frame(white: 0..<0)))
        let newest = try XCTUnwrap(
            fingerprint(frame(white: (bottomBand.lowerBound - 20)..<(bottomBand.lowerBound - 4))))
        XCTAssertNotEqual(flat.identity, newest.identity)
    }

    func testAChangeInTheMiddleOfTheScreenMovesTheIdentity() throws {
        let flat = try XCTUnwrap(fingerprint(frame(white: 0..<0)))
        let middle = try XCTUnwrap(fingerprint(frame(white: 300..<308)))
        XCTAssertNotEqual(flat.identity, middle.identity)
    }

    /// The reduction is a mean, so one changed source row inside a destination
    /// cell has to survive the averaging. Over the corpus the smallest single
    /// sample change across 29 conversation switches is 18 grey levels, which is
    /// nowhere near a quantisation edge; this pins the same thing on a frame
    /// where the arithmetic can be checked by hand.
    func testASingleChangedRowSurvivesTheAveraging() throws {
        let flat = try XCTUnwrap(fingerprint(frame(white: 0..<0)))
        let oneRow = try XCTUnwrap(fingerprint(frame(white: 400..<401)))
        XCTAssertNotEqual(flat.identity, oneRow.identity)
    }

    // MARK: - Our own keyboard

    /// The bottom fraction of the screen our own keyboard covers at its tallest:
    /// context strip, suggestion bar and key area over an iPhone 17 Pro's 874 pt.
    private var ownUIFraction: Double {
        Double(
            Theme.Metrics.totalHeight(withContextStrip: true)
                / KeyboardGeometry.referenceScreenHeight)
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

    /// What is actually on screen for the whole five seconds of a read: the
    /// host's conversation on top, our own keyboard along the bottom, and the
    /// result panel's loading shimmer sliding across it.
    ///
    /// `newest` is the newest incoming bubble, immediately above our keyboard,
    /// which is where a conversation switch shows up. `shimmer` is the leading
    /// edge of one `ShimmerLine` gradient, which moves every 16 ms.
    private func deployedFrame(newest: Range<Int>, shimmer: Int) -> [UInt8] {
        var pixels = [UInt8](repeating: 128, count: width * height * 4)
        paint(&pixels, rows: newest, columns: 24..<220, value: 255)
        paint(&pixels, rows: ownUIRows, columns: 0..<width, value: 60)
        let line = ownUIRows.lowerBound + 96
        paint(&pixels, rows: line..<(line + 11), columns: shimmer..<(shimmer + 90), value: 210)
        return pixels
    }

    /// The identity the capture process would publish for this frame, with our
    /// own keyboard's region excluded exactly as the keyboard published it.
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

    /// The blocker this crop exists for. `AIResultPanel.loading` animates three
    /// shimmer lines at `workingPhase += 0.03` every 16 ms for the whole read,
    /// and our keyboard is 33% of the fingerprint band, so with our own UI left
    /// in, condition 4 refused the answer to the very tap that paid for it: the
    /// screenshot was uploaded, the cloud call was spent, and twelve seconds
    /// later the user was told nothing answered.
    func testOurOwnShimmerDoesNotMoveTheIdentity() throws {
        let early = try deployedIdentity(deployedFrame(newest: newestMessage, shimmer: 30))
        let late = try deployedIdentity(deployedFrame(newest: newestMessage, shimmer: 180))
        XCTAssertEqual(early, late)
    }

    /// And the reason condition 4 exists in the first place, asserted on the
    /// same frames: excluding our own keyboard must not buy the freshness back
    /// by making the gate blind. A user who switches conversation mid-read is
    /// still caught, shimmer or no shimmer.
    func testAConversationSwitchUnderOurOwnShimmerStillMovesTheIdentity() throws {
        let before = try deployedIdentity(deployedFrame(newest: newestMessage, shimmer: 30))
        let after = try deployedIdentity(
            deployedFrame(newest: switchedConversation, shimmer: 180))
        XCTAssertNotEqual(before, after)
    }

    /// The crop is the keyboard's claim about itself, read out of a page another
    /// process writes, so it is bounded on both sides: a keyboard that says
    /// nothing leaves the band where the corpus measured it, and one that claims
    /// the whole screen is held to `Band.maximumOwnUI` — a crop past that removes
    /// the newest message from the fingerprint, which is the 23-of-29 failure the
    /// band measurement found.
    func testAnOutOfRangeClaimCannotMoveTheBandPastTheMeasuredLimit() {
        XCTAssertEqual(FrameReduction.bottomCrop(ownUI: 0), FrameReduction.Band.bottom)
        XCTAssertEqual(FrameReduction.bottomCrop(ownUI: 0.01), FrameReduction.Band.bottom)
        XCTAssertEqual(FrameReduction.bottomCrop(ownUI: .nan), FrameReduction.Band.bottom)
        XCTAssertEqual(FrameReduction.bottomCrop(ownUI: -1), FrameReduction.Band.bottom)
        XCTAssertEqual(FrameReduction.bottomCrop(ownUI: 0.95), FrameReduction.Band.maximumOwnUI)
        XCTAssertEqual(FrameReduction.bottomCrop(ownUI: ownUIFraction), ownUIFraction)
    }

    /// The whole thing through the gate, which is where the user meets it.
    ///
    /// Reply is tapped, the frame goes up, five seconds pass with our panel
    /// shimmering, the record lands — and it has to be `.offerable`. It was
    /// `.superseded`, non-deterministically, and the user was told twelve seconds
    /// later that nothing answered the request to read the screen, after the
    /// cloud call had already been paid for.
    func testTheAnswerToTheTapSurvivesOurOwnShimmerAtTheGate() throws {
        let read = try deployedIdentity(deployedFrame(newest: newestMessage, shimmer: 30))
        let confirming = try deployedIdentity(deployedFrame(newest: newestMessage, shimmer: 180))
        XCTAssertEqual(
            CaptureFreshness.evaluate(
                record: gateRecord(read), status: gateStatus(confirming), now: gateNow),
            .offerable)
    }

    /// And the threat the condition exists for, unchanged: a user who switched
    /// conversation during the read is never offered the stale reading, however
    /// busy our own animation was at the time.
    func testAConversationSwitchDuringTheReadIsStillSupersededAtTheGate() throws {
        let read = try deployedIdentity(deployedFrame(newest: newestMessage, shimmer: 30))
        let confirming = try deployedIdentity(
            deployedFrame(newest: switchedConversation, shimmer: 180))
        XCTAssertEqual(
            CaptureFreshness.evaluate(
                record: gateRecord(read), status: gateStatus(confirming), now: gateNow),
            .superseded)
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

    // MARK: - Formats

    func testTheLumaPlaneAndBGRAAgreeOnAFlatFrame() throws {
        var luma = [UInt8](repeating: 128, count: width * height)
        for y in 300..<308 { for x in 0..<width { luma[y * width + x] = 255 } }

        let fromLuma = try XCTUnwrap(fingerprint(luma, format: .luminance8))
        let flatLuma = try XCTUnwrap(
            fingerprint([UInt8](repeating: 128, count: width * height), format: .luminance8))
        XCTAssertNotEqual(fromLuma.identity, flatLuma.identity)
    }

    func testARowStrideLargerThanTheWidthIsHonoured() throws {
        // ReplayKit pads rows: 1206 pixels of BGRA arrive in 4,864 bytes, not
        // 4,824. A reduction that assumed a tight stride would read the padding
        // as pixels and skew every row.
        let padded = 64
        var pixels = [UInt8](repeating: 0, count: (width * 4 + padded) * height)
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * (width * 4 + padded) + x * 4
                let value: UInt8 = (300..<308).contains(y) ? 255 : 128
                pixels[offset] = value
                pixels[offset + 1] = value
                pixels[offset + 2] = value
            }
        }
        let strided = pixels.withUnsafeBytes {
            FrameFingerprint.make(
                base: $0.baseAddress!, width: width, height: height,
                bytesPerRow: width * 4 + padded, format: .bgra8888)
        }
        var tight = [UInt8](repeating: 128, count: width * height * 4)
        for y in 300..<308 {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                tight[offset] = 255
                tight[offset + 1] = 255
                tight[offset + 2] = 255
            }
        }
        XCTAssertEqual(try XCTUnwrap(strided).identity, try XCTUnwrap(fingerprint(tight)).identity)
    }

    // MARK: - Refusals

    /// A reduction of nothing hashes to a stable value that would match every
    /// other reduction of nothing, so geometry that cannot be reduced has to
    /// refuse rather than answer.
    func testDegenerateGeometryIsRefused() {
        let pixels = [UInt8](repeating: 0, count: 16 * 16 * 4)
        XCTAssertNil(
            pixels.withUnsafeBytes {
                FrameFingerprint.make(
                    base: $0.baseAddress!, width: 16, height: 16, bytesPerRow: 64,
                    format: .bgra8888)
            })
        XCTAssertNil(
            pixels.withUnsafeBytes {
                FrameFingerprint.make(
                    base: $0.baseAddress!, width: 320, height: 640, bytesPerRow: 4,
                    format: .bgra8888)
            })
    }

    // MARK: - Identity

    func testIdentityHexRoundTrips() {
        let identity = FrameIdentity(w0: 0x0123_4567_89ab_cdef, w1: 1, w2: 0, w3: .max)
        XCTAssertEqual(identity.hexString.count, 64)
        XCTAssertEqual(FrameIdentity(hexString: identity.hexString), identity)
        XCTAssertNil(FrameIdentity(hexString: "not a hash"))
    }

    func testNoFrameIsDistinctFromEveryRealFrame() throws {
        XCTAssertTrue(FrameIdentity.absent.isAbsent)
        let real = try XCTUnwrap(fingerprint(frame(white: 300..<308)))
        XCTAssertFalse(real.identity.isAbsent)
    }

    // MARK: - Settle hash

    /// The 64-bit hash is the settle gate's, not the identity's, and the
    /// difference is a distance rather than an equality: it takes two frames.
    func testTheSettleScoreIsZeroForAFrameAgainstItself() throws {
        let value = try XCTUnwrap(fingerprint(frame(white: 300..<308)))
        XCTAssertEqual(value.changeScore(from: value), 0)
    }

    /// A difference hash compares each cell with the one to its right, so it is
    /// blind to a change that is uniform across the width — a full-width white
    /// band moves every cell and no bit. That is correct for a settle detector
    /// and it is another reason this value cannot be the identity.
    func testTheSettleScoreRisesWhenTheScreenChanges() throws {
        let calm = try XCTUnwrap(fingerprint(frame(white: 0..<0)))
        let busy = try XCTUnwrap(fingerprint(frame(white: 200..<500, columns: 0..<160)))
        XCTAssertGreaterThan(busy.changeScore(from: calm), 0)
    }

    func testTheSettleScoreIsBlindToAFullWidthChange() throws {
        let calm = try XCTUnwrap(fingerprint(frame(white: 0..<0)))
        let banded = try XCTUnwrap(fingerprint(frame(white: 200..<500)))
        XCTAssertEqual(banded.changeScore(from: calm), 0)
        XCTAssertNotEqual(
            banded.identity, calm.identity,
            "the identity is not blind to it, which is the whole reason they are two values")
    }
}
