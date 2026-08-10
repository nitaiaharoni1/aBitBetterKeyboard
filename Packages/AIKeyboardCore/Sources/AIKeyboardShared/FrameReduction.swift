import Foundation

// MARK: - Reduction

/// The 32x64 greyscale reduction every fingerprint is taken over, and the band
/// of the frame it covers.
///
/// **Both the band and the value were measured, and the measurement changed the
/// design three times.** `Bar/screen-context/harness/frame-hash.mjs` renders each
/// of the 30 corpus scenes seven ways — as-is, with every message's glyphs
/// substituted inside its own script, with only the *newest* message's glyphs
/// substituted, with only the status-bar clock and the header presence line
/// moved, and then three renders with **our own keyboard on screen**: the AI
/// result panel loading at shimmer phase 0.10, the same at phase 0.60, and the
/// newest message's glyphs substituted under it. Then, per band and per value,
/// four columns:
///
/// | Band removed | Value | miss | false | own miss | own false |
/// |---|---|---|---|---|---|
/// | top 6.5% / bottom 45% | `sha256` | **23/29** | **19/30** | 3/29 | 0/30 |
/// | top 6.5% / bottom 8.5% | `sha256` | 0/29 | **19/30** | 0/29 | **30/30** |
/// | top 14% / bottom 8.5% | `sha256` | **0/29** | **0/30** | 0/29 | **30/30** |
/// | top 14% / bottom 8.5% | 64-bit dHash | **10/29** | 0/30 | 4/29 | **25/30** |
/// | **top 14% / bottom 33.4% (ours excluded)** | **`sha256`** | 20/29 | **0/30** | **0/29** | **0/30** |
/// | top 14% / bottom 40% (the cap) | `sha256` | 20/29 | 0/30 | **0/29** | **0/30** |
///
/// *miss* and *false* are measured with the host's own keyboard, *own miss* and
/// *own false* with ours. Three things follow, and none is obvious from outside.
///
/// **Cropping a fixed bottom 45% "where our own keyboard sits" is wrong**: it
/// removes the newest message from the fingerprint on screens where no keyboard
/// is up, so 23 of 29 conversation switches hash identically and no width of
/// hash rescues one of them. 64 bits is not enough even over the right band: 10
/// of 29 collide.
///
/// **But leaving our keyboard *in* is also wrong, and that one shipped.** The
/// `own false` column is the state every real reading is measured in — the user
/// tapped Reply on our keyboard, so it is on screen for the whole five-second
/// read with `AIResultPanel.loading` repainting three shimmer lines at 60 Hz —
/// and over the band that keeps it, **30 of 30** frames get a new identity from
/// nothing but our own animation. The freshness gate then retires the answer to
/// the tap that paid for it.
///
/// **So the band is chosen per frame, from what the keyboard publishes**
/// (`bottomCrop(ownUI:)`): the top 14% / bottom 8.5% that `VisionScreenReader.Band`
/// reads message lines from when no keyboard of ours is up, and that band with
/// our own rows removed when one is. Each is 0 and 0 in the column pair that
/// applies to it, and the 20/29 in the *miss* column of the last two rows is that
/// split rather than a defect: those bands are never used on a frame our keyboard
/// is absent from. `Band.maximumOwnUI` is the last row — the cap a bad claim from
/// the other process is held to, measured rather than assumed.
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

        /// The most of a frame's bottom our own keyboard may remove, whatever it
        /// claims.
        ///
        /// The crop below is a number one process reads out of a page another
        /// writes, and an over-large one is not a cosmetic error: cropping the
        /// bottom 45% of the frame removes the newest message from the
        /// fingerprint and misses **23 of 29** conversation switches, which is
        /// the failure the whole band measurement exists to prevent. Our
        /// **This is a ceiling on how tall the keyboard may be, and the action row
        /// is what made it bind.** It was 0.40, chosen against a 292 pt keyboard
        /// (33.4%) where nothing real ever reached it. `ActionBanner` and the
        /// action row took the keyboard to 372 pt of an iPhone 17 Pro's 874 —
        /// 0.4256 — and the clamp started binding, which left about 22 pt of our
        /// own banner inside the band. The banner shimmers for the whole of a read,
        /// so that is the 30-of-30 failure again: every frame takes a fresh
        /// identity from our own loading state and the freshness gate retires the
        /// answer the user's tap just paid a cloud call for.
        ///
        /// **The obvious fix — raise the ceiling to fit the taller keyboard — was
        /// measured and is wrong.** `run-fingerprint.sh` takes `OWN_UI_POINTS`, so
        /// the cliff was swept over the same 30 scenes rather than reasoned about.
        /// The arithmetic said 22 pt was far under a message bubble and safe. It is
        /// not:
        ///
        /// | our UI | crop | misses | false invalidations |
        /// |---|---|---|---|
        /// | 292 pt (before the action row) | 0.3340 | 0/29 | 0/30 |
        /// | 356 pt | 0.4073 | 0/29 | 0/30 |
        /// | **364 pt (shipping)** | **0.4165** | **0/29** | **0/30** |
        /// | 368 pt | 0.4210 | 0/29 | 0/30 |
        /// | 370 pt | 0.4233 | **1/29** | 0/30 |
        /// | 372 pt | 0.4256 | **1/29** | 0/30 |
        /// | 385 pt | 0.4405 | 1/29 | 0/30 |
        ///
        /// The cliff is between 368 and 370 pt, and it is sharp: `ml-04`'s two
        /// conversations collide the moment the crop passes it, because that much
        /// of the bottom takes the newest message with it. It is the same cliff
        /// `frame-hash.mjs` found at bottom-45%, where 23 of 29 switches are missed
        /// — this is its near edge rather than a second one.
        ///
        /// So 0.42 is the ceiling (367 pt), the keyboard ships at 364 pt with 6 pt
        /// of margin below the first failing measurement, and **the height of this
        /// keyboard is now a constraint rather than a preference**: adding a row,
        /// or growing the banner past `Theme.Metrics.bannerHeight`, costs a
        /// conversation switch. `CustomLayoutTests` holds the shipped total under
        /// this; the layout editor can still exceed it, which is the user's choice
        /// to make and degrades only screen context.
        public static let maximumOwnUI = 0.42
    }

    /// How much of the bottom to remove, given how much of the screen our own
    /// keyboard says it is covering.
    ///
    /// **Our own UI is not part of "which screen is this", and leaving it in was
    /// a shipping blocker.** `AIResultPanel.loading` animates three shimmer lines
    /// at 60 Hz for the whole five seconds of a read, and the keyboard is 32% of
    /// the fingerprint band on an iPhone 17 Pro, so condition 4 retired the
    /// answer to the very tap that paid for it: the frame was uploaded, the cloud
    /// call was spent, and the user was told nothing answered. Removing the
    /// keyboard's own rows costs no host content at all — while the keyboard is
    /// up, everything below its top edge *is* the keyboard.
    ///
    /// Zero, absent or smaller than the composer crop all mean the same thing:
    /// leave the band where the corpus measured it.
    public static func bottomCrop(ownUI fraction: Double) -> Double {
        guard fraction.isFinite, fraction > Band.bottom else { return Band.bottom }
        return min(fraction, Band.maximumOwnUI)
    }

    /// The rows of a frame of this height that the fingerprint is taken over.
    ///
    /// Public because a caller reproducing this arithmetic gets it wrong: the
    /// rounding here is `.rounded()`, and a test that truncated instead put a
    /// row it believed was cropped inside the band.
    public static func bandRows(
        inHeight height: Int, bottomCrop: Double = Band.bottom
    )
        -> Range<Int>
    {
        slice(height, fromStart: Band.top, fromEnd: bottomCrop)
    }

    /// How the buffer's rows and columns are laid out against the screen the user
    /// is looking at. ReplayKit hands this over as a sample attachment
    /// (`RPVideoSampleOrientationKey`) and nothing in the pixel data says it.
    public enum Orientation: Sendable, Equatable {
        /// The buffer's first row is the top of the screen.
        case up
        /// Upside down: the buffer's *last* row is the top of the screen.
        case down
        /// Rotated a quarter turn, with the top of the screen along the buffer's
        /// first column.
        case right
        /// Rotated a quarter turn the other way: the top of the screen is along
        /// the buffer's last column.
        case left

        /// One bit each, so a session can record every orientation it saw in a
        /// single byte of the shared page. See `CaptureStatus.orientationsSeen`:
        /// a session that only ever reports `.up` cannot tell us whether the
        /// quarter turns are mapped the right way round, and knowing *that* is
        /// the difference between an unmeasured guess and a measured one.
        public var bit: UInt8 {
            switch self {
            case .up: return 1 << 0
            case .down: return 1 << 1
            case .right: return 1 << 2
            case .left: return 1 << 3
            }
        }

        public var name: String {
            switch self {
            case .up: return "up"
            case .down: return "down"
            case .right: return "right"
            case .left: return "left"
            }
        }
    }

    /// The region of the buffer the fingerprint is taken over, for a frame that
    /// may not be the right way up.
    ///
    /// **Why this exists at all.** The band is a claim about the *screen*: drop
    /// the top 14% — status bar and navigation bar, where the presence line
    /// changes on its own — and drop everything from the top of our own keyboard
    /// downwards, because our panel animates a shimmer for the whole length of a
    /// read and would otherwise give every frame a fresh identity. What is
    /// fingerprinted is the middle, which is where the messages are.
    /// `bandRows` expressed that claim as a range of buffer *rows*,
    /// which is only the same thing while the buffer is the right way up. Rotate
    /// the device and the top of the screen is a column edge; the band then holds
    /// neither the title nor an exclusion of our keyboard, and the freshness gate
    /// starts discarding readings the user paid for — the exact failure the
    /// exclusion was added to fix.
    ///
    /// **One thing here is a guess, and it is named.** Which physical rotation
    /// ReplayKit reports as `.right` rather than `.left` is not something this
    /// repo can settle: nothing has ever executed `processSampleBuffer`, because
    /// the simulator runtime ships no `replayd`. The arithmetic below is pinned by
    /// `FrameFingerprintTests` and is right by construction; the *assignment* of
    /// the two quarter turns is a coin the device flips. Getting it backwards
    /// swaps which end of the screen is cropped, which shows up immediately as a
    /// landscape read that never confirms — step (f) of
    /// `Scripts/measure-on-device.sh`. If it is backwards, swap these two cases
    /// and nothing else.
    public static func bandRect(
        inWidth width: Int,
        height: Int,
        orientation: Orientation = .up,
        bottomCrop: Double = Band.bottom
    ) -> (columns: Range<Int>, rows: Range<Int>) {
        switch orientation {
        case .up:
            return (0..<width, slice(height, fromStart: Band.top, fromEnd: bottomCrop))
        case .down:
            return (0..<width, slice(height, fromStart: bottomCrop, fromEnd: Band.top))
        case .right:
            return (slice(width, fromStart: Band.top, fromEnd: bottomCrop), 0..<height)
        case .left:
            return (slice(width, fromStart: bottomCrop, fromEnd: Band.top), 0..<height)
        }
    }

    /// One axis of the crop. Split out so both axes round identically: the
    /// rounding is `.rounded()`, and a caller that truncated instead put a row it
    /// believed was cropped inside the band.
    static func slice(_ extent: Int, fromStart: Double, fromEnd: Double) -> Range<Int> {
        let first = Int((Double(extent) * fromStart).rounded())
        let last = Int((Double(extent) * (1.0 - fromEnd)).rounded())
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

    // reduce(base:width:height:bytesPerRow:format:orientation:bottomCrop:into:)
    // is in FrameReduction+Reduce.swift.
}
