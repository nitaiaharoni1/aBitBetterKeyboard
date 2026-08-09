import Foundation

// MARK: - Clock

/// The one clock both ends of the channel read.
///
/// `CLOCK_MONOTONIC_RAW` rather than a wall clock, and the difference is not
/// pedantry. Every timestamp in `CaptureStatus` is compared against *now* in a
/// different process to decide whether a reading may be shown, so a clock the
/// user or NTP can move is a clock that can make a forty-second-old reading look
/// fresh. This one cannot be set, is shared by every process on the machine, and
/// (unlike `CLOCK_UPTIME_RAW`) keeps counting while the device sleeps, so a phone
/// that spent ten minutes in a pocket comes back with a stale channel rather
/// than a live-looking one.
///
/// It resets at boot, which is handled by the session identifier rather than by
/// the clock: a page left over from before a reboot carries a session no live
/// reader recognises, and `CaptureFreshness` refuses a timestamp that is in the
/// future anyway.
public enum CaptureClock {

    public static func now() -> UInt64 { clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW) }

    public static func nanoseconds(_ seconds: Double) -> UInt64 {
        UInt64(max(0, seconds) * 1_000_000_000)
    }

    /// Elapsed nanoseconds, saturating at zero. A `then` in the future is not a
    /// small age, it is a lie — from a stale page, a reboot, or a torn read —
    /// and callers get `.max` so every freshness window rejects it.
    public static func elapsed(since then: UInt64, now: UInt64 = CaptureClock.now()) -> UInt64 {
        then == 0 ? .max : (now >= then ? now - then : .max)
    }
}

// MARK: - Status

/// What the capture process publishes about itself, 4 Hz plus a 1 Hz heartbeat.
///
/// Fixed layout, plain integers, no references and no optionals: the bytes are
/// memcpy'd in and out of a shared page and are read by a process that may see
/// them mid-write, so every bit pattern this struct can hold has to be a value
/// rather than a crash. Enumerations are stored as their raw `UInt8` and
/// converted after the seqlock has said the read was clean.
///
/// It carries `currentFrameIdentity` **and** `currentFrameSampledAt` **and**
/// `lastFrameAt` **and** `paused`, and all four are load-bearing. A design that
/// ships three of them has the stale-reading bug the whole freshness gate exists
/// to close: see `CaptureFreshness`, where conditions 2 and 3 are each the only
/// thing standing between the user and a reply written about a conversation they
/// have already left.
public struct CaptureStatus: Equatable, Sendable {

    // MARK: Session

    /// The broadcast session's UUID, high and low words. Zero means no session
    /// has ever run against this page.
    public var sessionHigh: UInt64 = 0
    public var sessionLow: UInt64 = 0

    /// `CaptureClock` nanoseconds.
    public var startedAt: UInt64 = 0

    // MARK: Liveness — three different failures, three different fields

    /// Written by the 1 Hz heartbeat and by nothing else. Proves the *process* is
    /// alive, including through a wedged delivery path.
    public var heartbeatAt: UInt64 = 0

    /// Written when a frame is delivered. Proves *delivery* is alive. A stalled
    /// handler ticks the heartbeat and not this, which is the whole reason they
    /// are separate fields.
    public var lastFrameAt: UInt64 = 0

    /// When the frame `currentFrameIdentity` describes was sampled. Written in
    /// the same seqlock transaction as the identity, always. An identity without
    /// its timestamp is a lie waiting to happen: it is what lets a reading be
    /// confirmed against a frame observed *before* the read even started.
    public var currentFrameSampledAt: UInt64 = 0

    public var currentFrameIdentity = FrameIdentity.absent

    // MARK: Counters

    public var framesDelivered: UInt32 = 0
    public var framesSampled: UInt32 = 0
    public var readsRequested: UInt32 = 0
    public var readsStarted: UInt32 = 0
    public var readsCompleted: UInt32 = 0
    /// Reads the memory governor refused. See `MemoryGovernor`; `degraded` is the
    /// same fact as a flag.
    public var refusedMemory: UInt32 = 0
    public var refusedInFlight: UInt32 = 0

    // `refusedBudget` and `ScreenContextEndReason.overBudget` used to sit here for
    // a session/daily read budget. No budget was ever built, so nothing could
    // move either of them, and a counter the status screen renders but no code
    // writes is a zero the user is invited to trust. Deleted rather than
    // documented as aspirational; the field comes back with the budget.

    // The two secure-field counters the design put here are in `CaptureIntent`
    // instead, and the reason is not tidiness: this page has exactly one writing
    // *process* and the keyboard is not it. `SharedPage`'s lock serialises
    // threads, not processes, so a second process writing this page would tear it
    // with nothing to catch the tear. The guard runs in the keyboard, because the
    // keyboard is the only process that can see the focused field's traits at
    // all, so its counters go in the page the keyboard writes.

    // MARK: Flags

    /// `broadcastPaused()` has fired and `broadcastResumed()` has not.
    public var paused: UInt8 = 0
    /// The memory governor is above its watermark and refusing reads. Written by
    /// `MemoryGovernor` through `CaptureChannelWriter.setDegraded`, on the
    /// transition only. A visible degraded state beats a jetsam kill, because a
    /// kill ends the broadcast and only the user can restart it.
    public var degraded: UInt8 = 0
    /// `ScreenContextEndReason` raw value, `.none` while running.
    public var endReasonRaw: UInt8 = ScreenContextEndReason.none.rawValue
    private var padding0: UInt8 = 0
    private var padding1: UInt32 = 0

    // MARK: Device facts
    //
    // **These exist so the phone can answer without a Mac attached.** Everything
    // about ReplayKit in this repo is a prediction: the simulator ships no
    // `replayd`, so `processSampleBuffer` has never executed anywhere and the
    // frame's size, format, orientation and cost are guesses. The extension
    // already logs all of it, but reading a device log means a cable and a Mac.
    // Written here as well, they cross the App Group like everything else and the
    // app can simply show them — the same page the status screen already reads.
    //
    // Deliberately small and fixed-width: this struct is memcpy'd through a
    // shared page, so every field is a scalar with a defined bit pattern and the
    // whole block costs 20 bytes of the 256 the page holds. Nothing here gates
    // anything; it is all observation.

    /// The first delivered frame's dimensions, in pixels. Zero until one arrives,
    /// which is itself the answer to "do frames arrive at all".
    public var frameWidth: UInt16 = 0
    public var frameHeight: UInt16 = 0

    /// `CMFormatDescription`'s media subtype as a FourCC — `BGRA`, `420f`, `420v`.
    /// Zero means no frame has been described yet.
    public var pixelFormat: UInt32 = 0

    /// The most recent `CGImagePropertyOrientation` raw value, and a bitmask of
    /// every one seen this session. The mask is what answers whether rotation
    /// ever reaches us: a session that only ever reports `.up` cannot tell us
    /// whether `FrameReduction.Orientation.left` is mapped the right way round.
    public var orientationRaw: UInt8 = 0
    public var orientationsSeen: UInt8 = 0

    /// `broadcastPaused` / `broadcastResumed` counts. Saturating rather than
    /// wrapping, because "did it come back" is the question and 255 answers it as
    /// well as 300 would.
    public var pauseCount: UInt8 = 0
    public var resumeCount: UInt8 = 0

    /// Footprint in tenths of a megabyte: the process's cost before its first
    /// frame, and the highest it has been seen. Tenths because a broadcast upload
    /// extension is killed at roughly 50 MB and the interesting question is how
    /// much headroom a read leaves, which whole megabytes round away.
    public var baselineFootprintTenthsMB: UInt16 = 0
    public var peakFootprintTenthsMB: UInt16 = 0

    /// Frames that arrived and could not be fingerprinted — an unknown pixel
    /// format, or geometry the reduction refuses. Non-zero here means the
    /// freshness gate is blind for those frames.
    public var fingerprintFailures: UInt32 = 0

    public init() {}

    /// Which of the four orientations this session has actually delivered.
    public var orientationsDelivered: [FrameReduction.Orientation] {
        [.up, .down, .left, .right].filter { orientationsSeen & $0.bit != 0 }
    }

    public var baselineFootprintMB: Double? {
        baselineFootprintTenthsMB == 0 ? nil : Double(baselineFootprintTenthsMB) / 10
    }

    public var peakFootprintMB: Double? {
        peakFootprintTenthsMB == 0 ? nil : Double(peakFootprintTenthsMB) / 10
    }

    /// The pixel format as the four characters a `CMFormatDescription` prints,
    /// nil before any frame has been described.
    public var pixelFormatCode: String? {
        guard pixelFormat != 0 else { return nil }
        let bytes = [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: pixelFormat >> $0) }
        return String(bytes: bytes, encoding: .macOSRoman)
    }

    public var sessionID: UUID? {
        guard sessionHigh != 0 || sessionLow != 0 else { return nil }
        return UUID(high: sessionHigh, low: sessionLow)
    }

    public mutating func setSessionID(_ id: UUID) {
        (sessionHigh, sessionLow) = id.words
    }

    /// A raw value this build does not know is `.lost` rather than `.none`: the
    /// page says *something* ended, and reporting no ending for an ending that
    /// happened is the one direction that reads as "screen context is off".
    public var endReason: ScreenContextEndReason {
        ScreenContextEndReason(rawValue: endReasonRaw) ?? .lost
    }

    public var isPaused: Bool { paused != 0 }
    public var isDegraded: Bool { degraded != 0 }
}

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

// MARK: - UUID words

extension UUID {
    var words: (UInt64, UInt64) {
        let bytes = uuid
        var high: UInt64 = 0
        var low: UInt64 = 0
        withUnsafeBytes(of: bytes) { raw in
            for index in 0..<8 { high = (high << 8) | UInt64(raw[index]) }
            for index in 8..<16 { low = (low << 8) | UInt64(raw[index]) }
        }
        return (high, low)
    }

    init(high: UInt64, low: UInt64) {
        var bytes = [UInt8](repeating: 0, count: 16)
        for index in 0..<8 { bytes[index] = UInt8((high >> (8 * (7 - index))) & 0xff) }
        for index in 0..<8 { bytes[8 + index] = UInt8((low >> (8 * (7 - index))) & 0xff) }
        self.init(
            uuid: (
                bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
            ))
    }
}
