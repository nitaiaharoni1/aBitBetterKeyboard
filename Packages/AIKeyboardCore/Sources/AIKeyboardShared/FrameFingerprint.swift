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
    /// `bottomCrop` comes from `FrameReduction.bottomCrop(ownUI:)`, over the
    /// height the keyboard published in `CaptureIntent`. It must be the same for
    /// the frame a reading was taken from and for every frame that later
    /// confirms it: the gate's only content condition is exact equality, so a
    /// band that moves mid-read retires the reading as surely as a conversation
    /// switch does. That is why the keyboard publishes the height it can occupy
    /// rather than the one it currently occupies.
    public static func make(
        base: UnsafeRawPointer,
        width: Int,
        height: Int,
        bytesPerRow: Int,
        format: FrameReduction.PixelFormat,
        orientation: FrameReduction.Orientation = .up,
        bottomCrop: Double = FrameReduction.Band.bottom
    ) -> FrameFingerprint? {
        withUnsafeTemporaryAllocation(of: UInt8.self, capacity: FrameReduction.sampleCount) {
            reduction in
            reduction.initialize(repeating: 0)
            defer { reduction.deinitialize() }
            guard
                FrameReduction.reduce(
                    base: base, width: width, height: height, bytesPerRow: bytesPerRow,
                    format: format, orientation: orientation, bottomCrop: bottomCrop,
                    into: reduction)
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
