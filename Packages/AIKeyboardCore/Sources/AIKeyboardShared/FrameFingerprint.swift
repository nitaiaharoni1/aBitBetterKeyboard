import CryptoKit
import Foundation

// MARK: - Identity

/// A SHA-256 of one frame's 2,048-byte reduction, held as four words so the
/// whole thing is 32 bytes of plain integers and can sit inside a shared page.
///
/// Cryptographic rather than perceptual, and that is a privacy choice as well as
/// a matching one (`.claude/docs/screen-capture-design.md` §5.4). This value
/// supports exactly one operation — *are these the same reduction* — whereas a
/// perceptual hash also supports *are these similar*, which is the operation
/// that lets a per-screen identifier be clustered or matched against a corpus of
/// known screens. It never leaves the device and there is no reason to send it.
public struct FrameIdentity: Equatable, Hashable, Sendable, Codable {
    public var w0: UInt64
    public var w1: UInt64
    public var w2: UInt64
    public var w3: UInt64

    public init(w0: UInt64 = 0, w1: UInt64 = 0, w2: UInt64 = 0, w3: UInt64 = 0) {
        self.w0 = w0
        self.w1 = w1
        self.w2 = w2
        self.w3 = w3
    }

    /// No frame has been fingerprinted yet. Distinct from any real identity,
    /// because a SHA-256 of 2,048 bytes is not going to be zero.
    ///
    /// Named `absent` rather than `none` on purpose: `FrameIdentity.none` in a
    /// `FrameIdentity?` position resolves to `Optional.none`, so the two spell
    /// the same thing and mean opposite ones. That cost a test that passed
    /// against the wrong value.
    public static let absent = FrameIdentity()

    public var isAbsent: Bool { self == .absent }

    public init(digest: some Sequence<UInt8>) {
        var words: [UInt64] = [0, 0, 0, 0]
        for (index, byte) in digest.enumerated() where index < 32 {
            words[index / 8] = (words[index / 8] << 8) | UInt64(byte)
        }
        self.init(w0: words[0], w1: words[1], w2: words[2], w3: words[3])
    }

    /// SHA-256 over the reduction. The only way an identity is meant to be made.
    public init(reduction: UnsafeBufferPointer<UInt8>) {
        var hasher = SHA256()
        hasher.update(bufferPointer: UnsafeRawBufferPointer(reduction))
        self.init(digest: hasher.finalize())
    }

    public var hexString: String {
        [w0, w1, w2, w3].map { String(format: "%016llx", $0) }.joined()
    }

    public init?(hexString: String) {
        guard hexString.count == 64 else { return nil }
        var words: [UInt64] = []
        var index = hexString.startIndex
        for _ in 0..<4 {
            let end = hexString.index(index, offsetBy: 16)
            guard let word = UInt64(hexString[index..<end], radix: 16) else { return nil }
            words.append(word)
            index = end
        }
        self.init(w0: words[0], w1: words[1], w2: words[2], w3: words[3])
    }
}

// MARK: - Reduction

/// The 32x64 greyscale reduction every fingerprint is taken over, and the band
/// of the frame it covers.
///
/// **Both the band and the value were measured, and the measurement changed the
/// design twice.** `Bar/screen-context/harness/frame-hash.mjs` renders each of
/// the 30 corpus scenes four ways — as-is, with every message's glyphs
/// substituted inside its own script, with only the *newest* message's glyphs
/// substituted, and with only the status-bar clock and the header presence line
/// moved — and then counts, per band and per value, how many near pairs the
/// value fails to separate and how many chrome-only changes it wrongly
/// separates. Both columns have to be zero and exactly one configuration reaches
/// that:
///
/// | Band removed | Value | misses | false invalidations |
/// |---|---|---|---|
/// | top 6.5% / bottom 45% | `sha256` | **23/29** | 19/30 |
/// | top 6.5% / bottom 45% | 64-bit dHash | **23/29** | 3/30 |
/// | top 6.5% / bottom 8.5% | `sha256` | 0/29 | **19/30** |
/// | **top 14% / bottom 8.5%** | **`sha256`** | **0/29** | **0/30** |
/// | top 14% / bottom 8.5% | 64-bit dHash | **11/29** | 0/30 |
///
/// Two things that follow, and neither is obvious from the outside. Cropping the
/// bottom 45% "where our own keyboard sits" removes the newest message from the
/// fingerprint entirely, so 23 of 29 conversation switches hash identically and
/// no width of hash rescues a single one of them. And 64 bits is not enough even
/// over the right band: 11 of 29 collide. The band that works is the one
/// `VisionScreenReader.Band` already reads message lines from, which is a
/// pleasing consequence rather than a coincidence — the fingerprint now covers
/// exactly the region the reading is taken from.
public enum FrameReduction {

    public static let columns = 32
    public static let rows = 64
    public static let sampleCount = columns * rows  // 2,048 bytes

    /// Fractions of frame height removed before the reduction.
    ///
    /// `VisionScreenReader.Band` names these bottom-up, in Vision's coordinates:
    /// `statusBar = 0.935`, `navigationBar = 0.86`, `composer = 0.085`. Top-down
    /// that is the top 14% and the bottom 8.5%.
    ///
    /// The navigation bar is cropped for a measured reason, not a cosmetic one:
    /// it is where the presence line lives ("online" / "typing..."), and the
    /// presence line changes on its own. Leave it in and a chrome-only change
    /// moves the identity on 19 of 30 frames, each of which retires a good
    /// reading and buys a needless cloud read.
    public enum Band {
        public static let top = 0.14
        public static let bottom = 0.085
    }

    /// The rows of a frame of this height that the fingerprint is taken over.
    ///
    /// Public because a caller reproducing this arithmetic gets it wrong: the
    /// rounding here is `.rounded()`, and a test that truncated instead put a
    /// row it believed was cropped inside the band.
    public static func bandRows(inHeight height: Int) -> Range<Int> {
        let first = Int((Double(height) * Band.top).rounded())
        let last = Int((Double(height) * (1.0 - Band.bottom)).rounded())
        return first..<max(first, last)
    }

    /// How the source bytes are laid out. Only the three ReplayKit and CoreVideo
    /// can hand us; there is no general image decoding in this target and there
    /// must not be, because this code runs in a ~50 MB process.
    public enum PixelFormat: Sendable {
        /// 32 bits per pixel, blue first. `kCVPixelFormatType_32BGRA`.
        case bgra8888
        /// 32 bits per pixel, alpha first. `kCVPixelFormatType_32ARGB`.
        case argb8888
        /// One byte per pixel. The Y plane of `420YpCbCr8BiPlanar`, and what a
        /// greyscale test fixture hands in.
        case luminance8

        public var bytesPerPixel: Int {
            switch self {
            case .bgra8888, .argb8888: return 4
            case .luminance8: return 1
            }
        }
    }

    /// Box-averages the cropped band down to `columns` x `rows` greyscale.
    ///
    /// Reads the source exactly once, in row order, and allocates nothing beyond
    /// an 8 KB accumulator — the frame is never copied, scaled into a second
    /// buffer, or converted. That matters here more than it reads: one BGRA
    /// frame at 1206x2622 is 12.6 MB against a ~50 MB cap, so a fingerprint that
    /// needed its own copy of the frame would cost a quarter of the extension's
    /// budget to produce 2 KB.
    ///
    /// - Returns: false, leaving `destination` untouched, if the geometry is not
    ///   something that can be reduced. A refusal, never a zero-filled answer:
    ///   a reduction of nothing hashes to a stable identity that would match
    ///   every other reduction of nothing.
    @discardableResult
    public static func reduce(
        base: UnsafeRawPointer,
        width: Int,
        height: Int,
        bytesPerRow: Int,
        format: PixelFormat,
        into destination: UnsafeMutableBufferPointer<UInt8>
    ) -> Bool {
        guard destination.count >= sampleCount else { return false }
        guard width >= columns, height >= rows else { return false }
        guard bytesPerRow >= width * format.bytesPerPixel else { return false }

        let band = bandRows(inHeight: height)
        let firstRow = band.lowerBound
        let lastRow = band.upperBound
        let bandRows = band.count
        guard bandRows >= rows else { return false }

        let stride = format.bytesPerPixel

        return withUnsafeTemporaryAllocation(of: UInt32.self, capacity: sampleCount) { sums in
            sums.initialize(repeating: 0)
            defer { sums.deinitialize() }

            return withUnsafeTemporaryAllocation(of: UInt16.self, capacity: width) { columnOf in
                // Precomputed so the inner loop is a table lookup rather than a
                // multiply and a divide per pixel.
                for x in 0..<width { columnOf[x] = UInt16(x * columns / width) }

                for y in firstRow..<lastRow {
                    let destinationRow = (y - firstRow) * rows / bandRows
                    let rowBase = base.advanced(by: y * bytesPerRow)
                    let accumulator = sums.baseAddress! + destinationRow * columns

                    switch format {
                    case .luminance8:
                        let pixels = rowBase.assumingMemoryBound(to: UInt8.self)
                        for x in 0..<width {
                            accumulator[Int(columnOf[x])] &+= UInt32(pixels[x])
                        }
                    case .bgra8888, .argb8888:
                        let blueOffset = format == .bgra8888 ? 0 : 3
                        let greenOffset = format == .bgra8888 ? 1 : 2
                        let redOffset = format == .bgra8888 ? 2 : 1
                        let pixels = rowBase.assumingMemoryBound(to: UInt8.self)
                        for x in 0..<width {
                            let pixel = x * stride
                            // Rec. 601 luma in integer form: the same
                            // 0.299 / 0.587 / 0.114 the harness uses, scaled by
                            // 256 so the inner loop stays in integers.
                            let luma =
                                77 * UInt32(pixels[pixel + redOffset])
                                + 150 * UInt32(pixels[pixel + greenOffset])
                                + 29 * UInt32(pixels[pixel + blueOffset])
                            accumulator[Int(columnOf[x])] &+= luma >> 8
                        }
                    }
                }

                // Sample counts are the product of the two band widths rather
                // than a second accumulator: the row and column ranges are
                // deterministic, so counting them is arithmetic.
                for row in 0..<rows {
                    let rowSamples = bandRows * (row + 1) / rows - bandRows * row / rows
                    for column in 0..<columns {
                        let columnSamples = width * (column + 1) / columns - width * column / columns
                        let samples = rowSamples * columnSamples
                        guard samples > 0 else { return false }
                        let mean = sums[row * columns + column] / UInt32(samples)
                        destination[row * columns + column] = UInt8(min(mean, 255))
                    }
                }
                return true
            }
        }
    }
}

// MARK: - Fingerprint

/// What one sampled frame is worth keeping: an exact identity and a settle hash.
///
/// **Two values from one reduction, and they have different jobs.** `identity`
/// answers *is this the same screen* for the freshness gate's only
/// content-identity condition, where the test is exact equality and a collision
/// means a reply written about somebody else's message. `settleHash` answers
/// *has it stopped moving* for the throttle, where "uninformative" is the
/// correct property and nothing depends on the value being unique. Measured, the
/// same 64-bit perceptual hash that is right for the second job collides on 11
/// of 29 conversation switches and is disqualifying for the first.
public struct FrameFingerprint: Equatable, Sendable {

    public let identity: FrameIdentity

    /// A 64-bit difference hash of the same reduction. Compared against the
    /// previous frame's by `changeScore(from:)`; meaningless on its own.
    public let settleHash: UInt64

    public init(identity: FrameIdentity, settleHash: UInt64) {
        self.identity = identity
        self.settleHash = settleHash
    }

    /// How much moved between two frames, 0 (identical) to 1 (every bit).
    ///
    /// The design calls this a property of a fingerprint; it is a distance, so
    /// it takes two. A settle gate that watched a single frame's hash would have
    /// nothing to compare it to.
    public func changeScore(from previous: FrameFingerprint) -> Double {
        Double((settleHash ^ previous.settleHash).nonzeroBitCount) / 64.0
    }

    /// Fingerprints one frame in place. The pixels are read and not copied; the
    /// 2,048-byte reduction lives on the stack for the length of this call and is
    /// never written anywhere, because at 32x64 it is a bad picture but it is
    /// still a picture.
    public static func make(
        base: UnsafeRawPointer,
        width: Int,
        height: Int,
        bytesPerRow: Int,
        format: FrameReduction.PixelFormat
    ) -> FrameFingerprint? {
        withUnsafeTemporaryAllocation(of: UInt8.self, capacity: FrameReduction.sampleCount) {
            reduction in
            reduction.initialize(repeating: 0)
            defer { reduction.deinitialize() }
            guard
                FrameReduction.reduce(
                    base: base, width: width, height: height, bytesPerRow: bytesPerRow,
                    format: format, into: reduction)
            else { return nil }
            return make(reduction: UnsafeBufferPointer(reduction))
        }
    }

    /// The half that turns 2,048 samples into the two values. Split out so a
    /// test can drive it with a reduction it built itself.
    public static func make(reduction: UnsafeBufferPointer<UInt8>) -> FrameFingerprint? {
        guard reduction.count >= FrameReduction.sampleCount else { return nil }
        return FrameFingerprint(
            identity: FrameIdentity(reduction: reduction),
            settleHash: differenceHash(reduction))
    }

    /// 8x8 difference hash: one bit per cell, set when the cell is brighter than
    /// the one to its right. Taken over a 8x9 regrid of the reduction, which is
    /// what makes it perceptual — it survives a pixel of scroll and a repaint.
    private static func differenceHash(_ reduction: UnsafeBufferPointer<UInt8>) -> UInt64 {
        let side = 8
        func cell(_ row: Int, _ column: Int) -> Int {
            let y0 = row * FrameReduction.rows / side
            let y1 = max(y0 + 1, (row + 1) * FrameReduction.rows / side)
            let x0 = column * FrameReduction.columns / (side + 1)
            let x1 = max(x0 + 1, (column + 1) * FrameReduction.columns / (side + 1))
            var total = 0
            var count = 0
            for y in y0..<y1 {
                for x in x0..<x1 {
                    total += Int(reduction[y * FrameReduction.columns + x])
                    count += 1
                }
            }
            return total / max(count, 1)
        }

        var bits: UInt64 = 0
        for row in 0..<side {
            for column in 0..<side where cell(row, column) > cell(row, column + 1) {
                bits |= 1 << UInt64(row * side + column)
            }
        }
        return bits
    }
}
