import XCTest

@testable import AIKeyboardCore

/// The five conditions that decide whether a reading may be shown, one test per
/// condition failing on its own.
///
/// The scenario the whole gate exists to defeat is a reading from forty seconds
/// ago, from a different conversation, presented as current. Each test below
/// takes a situation that passes every condition and breaks exactly one, so a
/// condition that is quietly deleted fails here rather than showing a user a
/// reply written about somebody else's message.
final class CaptureFreshnessTests: XCTestCase {

    private let session = UUID()
    private let identity = FrameIdentity(w0: 1, w1: 2, w2: 3, w3: 4)
    private let now = CaptureClock.nanoseconds(1_000)

    /// A live producer that sampled a frame a moment ago.
    private func liveStatus(
        heartbeat: Double = 999.5,
        lastFrame: Double = 999.8,
        sampledAt: Double = 999.8,
        identity: FrameIdentity? = nil,
        paused: Bool = false,
        end: ScreenContextEndReason = .none
    ) -> CaptureStatus {
        var status = CaptureStatus()
        status.setSessionID(session)
        status.startedAt = CaptureClock.nanoseconds(900)
        status.heartbeatAt = CaptureClock.nanoseconds(heartbeat)
        status.lastFrameAt = CaptureClock.nanoseconds(lastFrame)
        status.currentFrameSampledAt = CaptureClock.nanoseconds(sampledAt)
        status.currentFrameIdentity = identity ?? self.identity
        status.paused = paused ? 1 : 0
        status.endReasonRaw = end.rawValue
        return status
    }

    /// A reading of the frame that status is showing, taken a second ago.
    private func record(
        identity: FrameIdentity? = nil,
        captured: Double = 999.0,
        read: Double = 999.5,
        session: UUID? = nil
    ) -> ScreenReadingRecord {
        ScreenReadingRecord(
            sessionID: session ?? self.session,
            requestSequence: 1,
            frameIdentity: identity ?? self.identity,
            capturedAt: CaptureClock.nanoseconds(captured),
            readAt: CaptureClock.nanoseconds(read),
            provenance: "cloud",
            sender: "Maya",
            message: "מתי אתה מגיע?",
            language: KeyboardLanguage.hebrew.rawValue)
    }

    // MARK: The happy path

    func testAConfirmedReadingOfTheCurrentFrameIsOfferable() {
        XCTAssertEqual(
            CaptureFreshness.evaluate(record: record(), status: liveStatus(), now: now),
            .offerable)
    }

    // MARK: 1 — the producer is alive

    /// A jetsam kill at the memory limit calls no ReplayKit callback at all, so
    /// the only evidence it happened is a heartbeat that stopped.
    func testAStaleHeartbeatIsAnEndingEvenWithNoRecordedReason() {
        XCTAssertEqual(
            CaptureFreshness.evaluate(
                record: record(), status: liveStatus(heartbeat: 990), now: now),
            .ended(.lost))
    }

    func testARecordedReasonBeatsTheInference() {
        XCTAssertEqual(
            CaptureFreshness.evaluate(
                record: record(), status: liveStatus(end: .stopped), now: now),
            .ended(.stopped))
    }

    /// A session that has begun and delivered no frame yet fails condition 2 the
    /// same way a stalled one does, and it is not the same thing: the user is
    /// still in Apple's picker or its countdown. Told apart by `lastFrameAt`
    /// never having been written.
    func testASessionThatHasSeenNoFrameYetIsStartingRatherThanPaused() {
        var status = liveStatus()
        status.lastFrameAt = 0
        status.currentFrameSampledAt = 0
        status.currentFrameIdentity = .absent

        XCTAssertEqual(CaptureFreshness.evaluate(status: status, now: now), .starting)
    }

    /// …and a session that has seen a frame and stopped seeing them is idle,
    /// which is the case the same field decides.
    func testASessionThatSawFramesAndStoppedIsIdle() {
        XCTAssertEqual(
            CaptureFreshness.evaluate(status: liveStatus(lastFrame: 990), now: now), .idle)
    }

    func testNoStatusAtAllIsNoSession() {
        XCTAssertEqual(CaptureFreshness.evaluate(status: nil, now: now), .noSession)
        XCTAssertEqual(CaptureFreshness.evaluate(status: CaptureStatus(), now: now), .noSession)
        XCTAssertEqual(CaptureFreshness.evaluate(reading: .absent, now: now), .noSession)
        XCTAssertEqual(
            CaptureFreshness.evaluate(reading: .settled(liveStatus()), now: now), .offerable)
    }

    /// A page that exists and will not settle is a producer that was killed
    /// between `begin_write` and `end_write`: the sequence is odd and no later
    /// event will ever close it, so every read fails for the rest of the session.
    ///
    /// It used to read as `.noSession`, so the strip said "screen context is off"
    /// and offered no way back while the user's broadcast was still switched on.
    /// A jetsam kill is an ending with a restart (§8.2), which is what the
    /// heartbeat-window case above already reports.
    func testAPageThatWillNotSettleIsAnEndingRatherThanNoSession() {
        XCTAssertEqual(CaptureFreshness.evaluate(reading: .unsettled, now: now), .ended(.lost))
        XCTAssertEqual(
            CaptureFreshness.evaluate(record: record(), reading: .unsettled, now: now),
            .ended(.lost),
            "a reading cannot be offered against a page nobody can read")
    }

    // MARK: 2 — delivery is alive

    func testAPausedBroadcastIsNotFresh() {
        XCTAssertEqual(
            CaptureFreshness.evaluate(record: record(), status: liveStatus(paused: true), now: now),
            .paused)
    }

    /// The failure with no callback behind it: the process is alive, the
    /// heartbeat ticks on its own timer, and frames have stopped arriving. Two
    /// fields because they are two failures.
    func testAFrameGapDoesNotCertifyAReading() {
        XCTAssertEqual(
            CaptureFreshness.evaluate(
                record: record(), status: liveStatus(lastFrame: 995), now: now),
            .idle,
            "nothing has confirmed that the conversation on screen is still the one that was read")
    }

    /// **The pause iOS reported and the gap this code inferred are different
    /// verdicts, and the difference is what the second one rests on.**
    ///
    /// `paused` is a fact: `broadcastPaused()` fired. A gap in `lastFrameAt` is an
    /// inference from `frameWindow`, and `frameWindow` was justified as "two
    /// 250 ms samples plus slack" over a delivery rate that has never been
    /// measured (R1). If ReplayKit turns out to deliver on change rather than on a
    /// clock, a user reading a still conversation produces no frames at all — and
    /// the old code answered `.paused` two seconds later, which took the Reply
    /// button off exactly the screen this feature exists for, with nothing in the
    /// UI to distinguish that from the feature being broken.
    func testAFrameGapIsIdleRatherThanPausedBecauseNobodyHasMeasuredTheDeliveryRate() {
        XCTAssertEqual(
            CaptureFreshness.evaluate(status: liveStatus(paused: true), now: now), .paused,
            "iOS said so")
        XCTAssertEqual(
            CaptureFreshness.evaluate(status: liveStatus(lastFrame: 995), now: now), .idle,
            "this code inferred it, from a rate nobody has measured")

        // An explicit pause outranks the inference: both hold here and the
        // reported fact is the one reported.
        XCTAssertEqual(
            CaptureFreshness.evaluate(status: liveStatus(lastFrame: 995, paused: true), now: now),
            .paused)
    }

    /// The window still has to fire for a session that has genuinely gone quiet,
    /// and it still has to not fire a moment before that.
    func testTheFrameWindowIsStillAWindow() {
        XCTAssertEqual(
            CaptureFreshness.evaluate(status: liveStatus(lastFrame: 998.5), now: now), .offerable,
            "1.5 s is inside the two-second window")
        XCTAssertEqual(
            CaptureFreshness.evaluate(status: liveStatus(lastFrame: 997.9), now: now), .idle,
            "2.1 s is outside it")
    }

    // MARK: 3 — the reading has been confirmed since it finished

    /// The hole the first revision of the design left open. If the read runs on
    /// the delivery callback, no frames are observed while it runs, so the
    /// published identity is frozen at the frame being read while the heartbeat
    /// keeps ticking — and a user who switches conversation mid-read passes
    /// conditions 1, 4 and 5 with a reading about the conversation they left.
    func testAReadingIsNotOfferableUntilAFrameIsSeenAfterItFinished() {
        XCTAssertEqual(
            CaptureFreshness.evaluate(
                record: record(captured: 990, read: 999.9),
                status: liveStatus(sampledAt: 999.5),
                now: now),
            .unconfirmed,
            "unconfirmed is a loading state, not a stale one: the reading is young")
    }

    func testConfirmationArrivesWithTheNextSample() {
        XCTAssertEqual(
            CaptureFreshness.evaluate(
                record: record(captured: 999.0, read: 999.5),
                status: liveStatus(lastFrame: 999.75, sampledAt: 999.75),
                now: now),
            .offerable)
    }

    // MARK: 4 — the content identity

    /// The only content condition in the table, and therefore the whole defence
    /// against the wrong conversation.
    func testADifferentScreenRetiresTheReading() {
        XCTAssertEqual(
            CaptureFreshness.evaluate(
                record: record(),
                status: liveStatus(identity: FrameIdentity(w0: 9, w1: 9, w2: 9, w3: 9)),
                now: now),
            .superseded)
    }

    /// A producer that has not fingerprinted anything publishes the zero
    /// identity. A record carrying the same zero would match it, which is how an
    /// unfingerprinted frame would confirm a reading of nothing.
    func testTheEmptyIdentityNeverConfirmsAnything() {
        XCTAssertEqual(
            CaptureFreshness.evaluate(
                record: record(identity: FrameIdentity.absent),
                status: liveStatus(identity: FrameIdentity.absent),
                now: now),
            .superseded)
    }

    // MARK: 5 — the backstop and the session

    func testAReadingOlderThanTheBackstopIsRetiredEvenIfThePixelsDidNotMove() {
        XCTAssertEqual(
            CaptureFreshness.evaluate(
                record: record(captured: 975, read: 975.5), status: liveStatus(), now: now),
            .superseded,
            "20 s is a guess and it is the fifth line of defence, but it is still a line")
    }

    func testAReadingFromAPreviousSessionIsNeverOfferable() {
        XCTAssertEqual(
            CaptureFreshness.evaluate(
                record: record(session: UUID()), status: liveStatus(), now: now),
            .superseded)
    }

    // MARK: The clock

    /// A timestamp in the future is not a small age. It comes from a page left
    /// over from before a reboot, or from a torn read, and every window has to
    /// reject it rather than compute a huge positive number by wrapping.
    func testATimestampInTheFutureIsRefused() {
        XCTAssertEqual(CaptureClock.elapsed(since: now + 1, now: now), .max)
        XCTAssertEqual(CaptureClock.elapsed(since: 0, now: now), .max)
        XCTAssertEqual(
            CaptureFreshness.evaluate(
                record: record(), status: liveStatus(heartbeat: 1_100), now: now),
            .ended(.lost))
    }
}
