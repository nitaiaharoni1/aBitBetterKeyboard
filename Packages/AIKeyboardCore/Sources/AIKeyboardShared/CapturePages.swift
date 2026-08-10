import Foundation

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
    /// `ScreenContextEndReason` raw value, `.notEnded` while running.
    public var endReasonRaw: UInt8 = ScreenContextEndReason.notEnded.rawValue
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
