import Foundation

// MARK: - Intent

/// What the keyboard asks of the capture process. The reverse direction, and
/// deliberately tiny: the keyboard has no way to make the extension do anything
/// except raise a number.
public struct CaptureIntent: Equatable, Sendable {

    /// Set while our keyboard is on screen. Advisory only — it gates nothing,
    /// because "the keyboard is visible" is not a proxy for "safe to upload": a
    /// keyboard is up in password fields, banking forms and 2FA prompts as often
    /// as in conversations.
    public var keyboardVisible: UInt8 = 0
    private var padding0: UInt8 = 0

    /// Per mille of the screen height our own keyboard is drawing on, measured
    /// from the bottom edge. Zero while it is not on screen.
    ///
    /// **The one thing in this page that gates anything, and it gates the frame
    /// fingerprint's band.** Our own UI is not part of "which screen is this":
    /// while the keyboard is up, everything below its top edge is ours, and
    /// `AIResultPanel.loading` repaints three shimmer lines there at 60 Hz for
    /// the whole five seconds of a read. Left inside the band, that moved
    /// `currentFrameIdentity` on every sample and the freshness gate retired the
    /// answer to the very tap that paid for it. `FrameReduction.bottomCrop(ownUI:)`
    /// is what reads this, and it bounds the claim on both sides — an absent or
    /// tiny value leaves the band where the corpus measured it, and an over-large
    /// one is held to `Band.maximumOwnUI`.
    ///
    /// Per mille rather than points because the producer sees pixels and does not
    /// know this device's scale factor, and as an integer because this struct is
    /// memcpy'd through a shared page and every bit pattern it can hold has to be
    /// a value. Written as *the tallest form* the keyboard can take, not the one
    /// it currently has: the context strip appears and disappears mid-read, and a
    /// band that moves retires readings exactly as a conversation switch does.
    public var ownUIHeightPermille: UInt16 = 0
    private var padding2: UInt32 = 0

    /// When `keyboardVisible` was last written, in `CaptureClock` nanoseconds.
    ///
    /// A flag without a timestamp is the same mistake as an identity without
    /// one. The keyboard extension is killed rather than dismissed often enough
    /// that a `1` left in this page outlives the process that wrote it, and a
    /// producer reading the bare flag would believe a keyboard that is not there.
    public var keyboardVisibleAt: UInt64 = 0

    /// Monotonically increasing. The user tapped Reply; the extension reads the
    /// next settled frame and stamps the record with this number, so the
    /// keyboard can tell the answer to *its* tap from the answer to the last one.
    public var readNow: UInt64 = 0

    /// When `readNow` was last raised, in `CaptureClock` nanoseconds. Lets the
    /// producer ignore a request that has been sitting in the page since before
    /// it started.
    public var readRequestedAt: UInt64 = 0

    /// Taps on Reply the secure-field guard refused because the focused field
    /// said it was a secure text entry field, or named a content type in
    /// `SecureField.sensitive`.
    public var refusedSecure: UInt32 = 0

    /// Taps refused because the focused field did not answer at all.
    ///
    /// **Counted apart from `refusedSecure` because the two say different things
    /// about the guard rather than about the field.** `isSecureTextEntry` is an
    /// `@optional` trait, so a host that never implements it sends every tap
    /// here, and the guard fails closed — meaning that on such a host the guard
    /// has quietly switched the feature off. Whether hosts populate the trait
    /// through a `UITextDocumentProxy` at all is an open question no simulator
    /// can settle, and this is what turns it into a number: after a device run,
    /// taps are `readNow + refusedSecure + refusedSecureUnknown`, so this
    /// counter standing equal to the tap count is the answer "no host ever
    /// answers". The resolution then is to find a different signal, never to
    /// flip the default.
    public var refusedSecureUnknown: UInt32 = 0

    public init() {}

    public var isKeyboardVisible: Bool { keyboardVisible != 0 }

    /// `ownUIHeightPermille` as the fraction the reduction wants. 0 when the
    /// keyboard has never published one, which is a real answer: it means leave
    /// the band alone.
    public var ownUIHeightFraction: Double { Double(ownUIHeightPermille) / 1000 }

    /// Rounded and clamped on the way in, so nothing downstream has to wonder
    /// whether the page holds a fraction, a percentage or a NaN.
    public mutating func setOwnUIHeightFraction(_ fraction: Double) {
        guard fraction.isFinite, fraction > 0 else {
            ownUIHeightPermille = 0
            return
        }
        ownUIHeightPermille = UInt16((fraction * 1000).rounded().clamped(to: 0...1000))
    }

    /// The bottom fraction of a frame the fingerprint must leave out, given what
    /// the keyboard published here. The producer reads this and nothing else, so
    /// the bounding lives in one place.
    public var frameBottomCrop: Double {
        FrameReduction.bottomCrop(ownUI: ownUIHeightFraction)
    }
}

extension Double {
    fileprivate func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
