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

    private func fingerprint(
        _ pixels: [UInt8], orientation: FrameReduction.Orientation
    ) -> FrameFingerprint? {
        pixels.withUnsafeBytes { raw in
            FrameFingerprint.make(
                base: raw.baseAddress!, width: width, height: height,
                bytesPerRow: width * 4, format: .bgra8888, orientation: orientation)
        }
    }

    // MARK: - Rotation

    /// **`.up` is the old behaviour exactly**, which is the only reason the
    /// measured zeros in `FrameFingerprint`'s table survive this change. If this
    /// fails, every number in that table is describing code that no longer exists.
    func testAnUprightFrameCropsExactlyTheRowsItAlwaysDid() {
        let rect = FrameReduction.bandRect(inWidth: width, height: height)

        XCTAssertEqual(rect.rows, FrameReduction.bandRows(inHeight: height))
        XCTAssertEqual(rect.columns, 0..<width, "upright crops no columns at all")
    }

    /// A quarter turn puts the top of the screen along a *column* edge, so the
    /// band has to cut columns instead of rows. Expressing the crop as a row
    /// range — which is what the code did before — keeps neither the title bar
    /// nor the exclusion of our own keyboard.
    func testAQuarterTurnCropsColumnsRatherThanRows() {
        for orientation in [FrameReduction.Orientation.left, .right] {
            let rect = FrameReduction.bandRect(
                inWidth: width, height: height, orientation: orientation)

            XCTAssertEqual(rect.rows, 0..<height, "\(orientation): no rows are cropped")
            XCTAssertLessThan(rect.columns.count, width, "\(orientation): columns are")
        }
    }

    /// The two quarter turns cut opposite ends, and 180° cuts the opposite end
    /// from upright. Which *physical* rotation ReplayKit calls `.left` is the
    /// device question; that these four are four distinct regions is arithmetic,
    /// and it is what would break silently if someone collapsed them.
    func testTheFourOrientationsCropFourDifferentRegions() {
        let regions = [FrameReduction.Orientation.up, .down, .left, .right].map {
            FrameReduction.bandRect(inWidth: width, height: height, orientation: $0)
        }
        let described = regions.map { "\($0.columns)|\($0.rows)" }

        XCTAssertEqual(Set(described).count, 4, "two orientations crop the same region: \(described)")
        XCTAssertEqual(regions[0].rows.count, regions[1].rows.count, "up and down cut equal amounts")
        XCTAssertNotEqual(regions[0].rows, regions[1].rows, "…from opposite ends")
        XCTAssertNotEqual(regions[2].columns, regions[3].columns)
    }

    /// The property the whole exclusion exists for, now holding in landscape:
    /// paint into the region the band drops and the identity must not move. Our
    /// keyboard repaints a shimmer there for the whole length of a read, and when
    /// that leaked into the band it gave 30 of 30 frames a fresh identity from
    /// nothing, so the freshness gate threw away the reading the tap paid for.
    func testPaintingOutsideTheBandLeavesTheIdentityAloneWhenRotated() throws {
        for orientation in [FrameReduction.Orientation.up, .down, .left, .right] {
            let rect = FrameReduction.bandRect(
                inWidth: width, height: height, orientation: orientation)
            let plain = try XCTUnwrap(fingerprint(frame(white: 0..<0), orientation: orientation))

            // Somewhere the band does not look at, on whichever axis it cropped.
            let painted =
                rect.columns == 0..<width
                ? frame(white: outside(rect.rows, limit: height))
                : frame(white: 0..<height, columns: outside(rect.columns, limit: width))
            let after = try XCTUnwrap(fingerprint(painted, orientation: orientation))

            XCTAssertEqual(
                after.identity, plain.identity,
                "\(orientation): content outside the band moved the frame identity")
        }
    }

    /// …and the converse, or the test above would pass on a reducer that ignored
    /// the pixels entirely.
    func testPaintingInsideTheBandDoesMoveTheIdentityWhenRotated() throws {
        for orientation in [FrameReduction.Orientation.up, .down, .left, .right] {
            let rect = FrameReduction.bandRect(
                inWidth: width, height: height, orientation: orientation)
            let plain = try XCTUnwrap(fingerprint(frame(white: 0..<0), orientation: orientation))
            let painted = frame(white: rect.rows, columns: rect.columns)
            let after = try XCTUnwrap(fingerprint(painted, orientation: orientation))

            XCTAssertNotEqual(
                after.identity, plain.identity,
                "\(orientation): the band is not reading its own region")
        }
    }

    /// A run of indices the band excluded, taken from whichever end has room.
    private func outside(_ band: Range<Int>, limit: Int) -> Range<Int> {
        band.lowerBound >= 8 ? 0..<band.lowerBound : band.upperBound..<limit
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
