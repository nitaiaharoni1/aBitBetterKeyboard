import Foundation

/// Whether a reading may be shown, right now, in the user's own name.
///
/// The scenario to defeat is a reading from forty seconds ago, from a different
/// conversation, presented as current. Time alone does not catch it — a user
/// switches conversation in two seconds — so the rule is content-addressed, with
/// time as a backstop, and it is applied at the instant the strip renders rather
/// than when the reading arrived.
///
/// Five conditions, all of which must hold. The `kind` in the table is there so
/// it stays visible that only **one** of them sees a switched conversation:
///
/// | # | Condition | Kind | Catches |
/// |---|---|---|---|
/// | 1 | `now - heartbeatAt <= 3 s` | liveness | the capture process is dead, jetsam kill included |
/// | 2 | not paused and `now - lastFrameAt <= 2 s` | liveness | alive but frames have stopped |
/// | 3 | `currentFrameSampledAt >= record.readAt` | liveness | the reading has been confirmed against a frame observed *after* it completed |
/// | 4 | `record.frameIdentity == currentFrameIdentity` | **content** | the user scrolled, switched conversation, switched app, or a message arrived |
/// | 5 | `now - capturedAt <= 20 s` and the session matches | timer | intent moved even though the pixels did not |
///
/// **Condition 3 is the one that is easy to leave out and the one that matters.**
/// `currentFrameIdentity` is only evidence if it is the identity of a frame the
/// extension actually observed. Run the read inline on the delivery callback and
/// no frames are observed for the five seconds it takes, so the identity freezes
/// at the frame being read while the heartbeat, on its own timer, keeps ticking.
/// A user who switches conversation mid-read then passes 1, 4 and 5 with a
/// record about somebody else's message. `broadcastPaused()` opens the same
/// window from the other side, which is condition 2.
///
/// There is no stale-but-shown verdict in this enumeration, deliberately. When
/// Reply is tapped and the gate refuses, the keyboard asks for a new read and
/// shows the loading state. A five-second wait is the honest answer; a stale
/// reply in the user's own name is not.
public enum CaptureFreshness {

    /// Condition 1. Longer than a heartbeat interval by enough to survive a
    /// scheduling hiccup, short enough that a killed extension is noticed before
    /// the user can act on it.
    public static let heartbeatWindow = CaptureClock.nanoseconds(3)
    /// Condition 2. Two 250 ms samples plus slack.
    public static let frameWindow = CaptureClock.nanoseconds(2)
    /// Condition 5, and **it is a guess.** The right way to set it is to
    /// instrument the interval between a screen settling and the Reply tap in
    /// real use and put the cap at p95. Until that data exists, 20 s is chosen to
    /// be shorter than the 40 s this feature's brief calls unacceptable and
    /// longer than the ~5 s a read takes, so a reading is never declared stale
    /// before it has been shown once. With condition 3 in place it is the fifth
    /// line of defence rather than the second.
    public static let maximumAge = CaptureClock.nanoseconds(20)

    public enum Verdict: Equatable, Sendable {
        /// Every condition holds. The strip may show this reading.
        case offerable
        /// Condition 1. The producer is gone; the strip shows `.ended` and a way
        /// to restart. `.lost` when nothing recorded a reason, which is what a
        /// jetsam kill looks like.
        case ended(ScreenContextEndReason)
        /// Condition 2. Alive, not looking. The strip says paused.
        case paused
        /// Condition 3. The reading is not stale, it is merely unconfirmed —
        /// no frame has been observed since it completed. The strip keeps the
        /// loading state; this normally resolves within one 250 ms sample.
        case unconfirmed
        /// Condition 4 or 5. There is a live session but this reading is not
        /// about what is on screen now. The strip shows the pre-tap offer.
        case superseded
        /// There is no channel, or no session has ever run. **Not** the verdict
        /// for a page that exists and will not settle: that is `.ended(.lost)`,
        /// because a page nobody will ever close is a producer that died holding
        /// it, and the user needs a restart rather than "screen context is off".
        case noSession
    }

    /// The producer half of the gate, from what the reader actually found.
    ///
    /// This overload exists for the one case the `CaptureStatus?` one cannot see.
    /// A page that will not settle is not an absent page: the producer opened a
    /// seqlock transaction and never closed it, which is what a jetsam kill
    /// between `begin_write` and `end_write` leaves behind, and there is no later
    /// event that will fix it — only a new session's `begin()`. Reported as
    /// `.noSession` it renders as "screen context is off" and offers no restart,
    /// while the user's broadcast is still switched on. §8.2 says a kill reads as
    /// stopped unexpectedly, so it does.
    public static func evaluate(
        reading: CaptureStatusReading, now: UInt64 = CaptureClock.now()
    ) -> Verdict {
        if reading == .unsettled { return .ended(.lost) }
        return evaluate(status: reading.status, now: now)
    }

    /// The whole gate, from what the reader actually found. See the overload
    /// above for why the unsettled page is not `.noSession`.
    public static func evaluate(
        record: ScreenReadingRecord,
        reading: CaptureStatusReading,
        now: UInt64 = CaptureClock.now()
    ) -> Verdict {
        if reading == .unsettled { return .ended(.lost) }
        return evaluate(record: record, status: reading.status, now: now)
    }

    /// The producer half of the gate: conditions 1 and 2, which do not need a
    /// record. Used by the strip before any reading exists, so it can tell
    /// "watching" from "stopped".
    ///
    /// A nil `status` here means *no page*. A page that exists and will not
    /// settle is a different verdict and reaches the gate through the
    /// `CaptureStatusReading` overload above.
    public static func evaluate(
        status: CaptureStatus?, now: UInt64 = CaptureClock.now()
    )
        -> Verdict
    {
        guard let status, status.sessionID != nil else { return .noSession }

        // A recorded reason wins over the inference, and it wins even while the
        // heartbeat is still inside its window: the producer said it stopped.
        if status.endReason != .none { return .ended(status.endReason) }

        // 1. Liveness of the process.
        guard CaptureClock.elapsed(since: status.heartbeatAt, now: now) <= heartbeatWindow else {
            return .ended(.lost)
        }

        // 2. Liveness of delivery. Separate failure, separate field.
        if status.isPaused { return .paused }
        guard CaptureClock.elapsed(since: status.lastFrameAt, now: now) <= frameWindow else {
            return .paused
        }

        return .offerable
    }

    /// The whole gate. `.offerable` here is the only state in which a reading
    /// may be put in front of the user.
    public static func evaluate(
        record: ScreenReadingRecord,
        status: CaptureStatus?,
        now: UInt64 = CaptureClock.now()
    ) -> Verdict {
        let producer = evaluate(status: status, now: now)
        guard producer == .offerable, let status else { return producer }

        // 5b. Same session. A restart makes every earlier reading unofferable
        // however recent it looks, because the identity space restarted with it.
        guard record.sessionID == status.sessionID else { return .superseded }

        // 3. Confirmed against a frame sampled after the read finished. Not a
        // staleness test: a reading that has not been confirmed yet is young,
        // not old, which is why this returns a different verdict from 4 and 5.
        guard status.currentFrameSampledAt >= record.readAt else { return .unconfirmed }

        // 4. The only content-identity condition in the table, and therefore the
        // whole defence against the wrong conversation. What makes one equality
        // test enough is measured rather than assumed: see `FrameReduction`.
        guard
            record.frameIdentity == status.currentFrameIdentity,
            !record.frameIdentity.isAbsent
        else { return .superseded }

        // 5a. The backstop.
        guard CaptureClock.elapsed(since: record.capturedAt, now: now) <= maximumAge else {
            return .superseded
        }

        return .offerable
    }
}
