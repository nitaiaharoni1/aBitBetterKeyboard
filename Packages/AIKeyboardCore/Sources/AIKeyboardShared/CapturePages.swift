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
    public var refusedMemory: UInt32 = 0
    public var refusedInFlight: UInt32 = 0
    public var refusedBudget: UInt32 = 0
    /// The focused field said it was a secure text entry field.
    public var refusedSecure: UInt32 = 0
    /// The focused field did not answer. Counted apart from `refusedSecure`
    /// because the two mean different things about the *guard*: `isSecureTextEntry`
    /// is an `@optional` trait, so a host that never implements it makes every
    /// tap land here, and a first device run where this counter equals the tap
    /// count means the guard has silently disabled the feature. That is a thing
    /// to discover from a number rather than from a hole in shipping code.
    public var refusedSecureUnknown: UInt32 = 0

    // MARK: Flags

    /// `broadcastPaused()` has fired and `broadcastResumed()` has not.
    public var paused: UInt8 = 0
    /// The memory governor is above its watermark and refusing reads. A visible
    /// degraded state beats a jetsam kill, because a kill ends the broadcast and
    /// only the user can restart it.
    public var degraded: UInt8 = 0
    /// `ScreenContextEndReason` raw value, `.none` while running.
    public var endReasonRaw: UInt8 = ScreenContextEndReason.none.rawValue
    private var padding0: UInt8 = 0
    private var padding1: UInt32 = 0

    public init() {}

    public var sessionID: UUID? {
        guard sessionHigh != 0 || sessionLow != 0 else { return nil }
        return UUID(high: sessionHigh, low: sessionLow)
    }

    public mutating func setSessionID(_ id: UUID) {
        (sessionHigh, sessionLow) = id.words
    }

    public var endReason: ScreenContextEndReason {
        ScreenContextEndReason(rawValue: endReasonRaw) ?? .interrupted
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
    private var padding1: UInt16 = 0
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

    public init() {}

    public var isKeyboardVisible: Bool { keyboardVisible != 0 }
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
