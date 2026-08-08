import Foundation
import XCTest

@testable import AIKeyboardCore

/// The keyboard's side of a real capture session, driven end to end.
///
/// Nothing is faked below the session: a real `CaptureChannelWriter` writes a
/// real mmap'd status page, a real `CaptureChannelReader` maps it back, and
/// `CaptureFreshness` decides what it means. Only the container is swapped for a
/// temporary directory, because this target carries no App Group entitlement.
///
/// **What it cannot cover.** The producer here is not a broadcast extension.
/// The iOS Simulator runtime ships no `replayd`, so no broadcast session can
/// start on this destination and `SampleHandler` is never called. Everything
/// about ReplayKit's half — that frames arrive, at what size, and that the
/// process survives its memory cap — needs a device.
@MainActor
final class ScreenContextConsumerTests: XCTestCase {

    private var directory: URL!
    private var writer: CaptureChannelWriter!
    private var channel: ScreenContextChannel!
    private var session: ScreenContextSession!

    private let screenA = FrameFingerprint(
        identity: FrameIdentity(w0: 11, w1: 12, w2: 13, w3: 14), settleHash: 0xA)
    private let screenB = FrameFingerprint(
        identity: FrameIdentity(w0: 21, w1: 22, w2: 23, w3: 24), settleHash: 0xB)

    override func setUp() async throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("channel-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        writer = try XCTUnwrap(CaptureChannelWriter(directory: directory))
        channel = ScreenContextChannel(reader: CaptureChannelReader(directory: directory))
        session = ScreenContextSession()
        session.startConsuming(channel, as: .keyboard)
    }

    override func tearDown() async throws {
        session.stopConsuming()
        session = nil
        channel = nil
        writer = nil
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: Helpers

    /// One poll of the page, which is what the keyboard does four times a second.
    private func step() {
        channel.poll()
    }

    /// A live session showing `screen`, with a reading of it that has been
    /// confirmed by a later frame — the only situation in which a reading may be
    /// put in front of the user.
    @discardableResult
    private func liveSessionWithAReading(
        of screen: FrameFingerprint, sender: String = "Maya", sequence: UInt64 = 0
    ) throws -> UUID {
        let sessionID = writer.begin()
        writer.recordFrame(screen)
        let readAt = CaptureClock.now()
        try writer.publish(
            ScreenReadingRecord(
                sessionID: sessionID,
                requestSequence: sequence,
                frameIdentity: screen.identity,
                capturedAt: readAt,
                readAt: readAt,
                provenance: "cloud",
                sender: sender,
                message: "Are we still on for 6?",
                language: KeyboardLanguage.english.rawValue))
        // Condition 3: the reading is only evidence once a frame has been
        // observed after it completed.
        writer.recordFrame(screen)
        step()
        return sessionID
    }

    // MARK: The six states

    func testNoProducerIsOff() {
        step()

        XCTAssertEqual(session.state, .off)
        XCTAssertEqual(session.source, .none)
        XCTAssertFalse(session.state.isVisible)
    }

    /// A session that has begun and delivered no frame is starting, not stalled.
    /// The user is in Apple's picker or its three-second countdown.
    func testABegunSessionWithNoFrameYetIsStarting() {
        writer.begin()

        step()

        XCTAssertEqual(session.state, .starting)
        XCTAssertEqual(session.source, .capture)
    }

    /// The normal state of a live session. There is no reading because a read
    /// only ever happens in answer to a tap on Reply.
    func testFramesWithNoReadingAreWatching() {
        writer.begin()
        writer.recordFrame(screenA)

        step()

        XCTAssertEqual(session.state, .watching)
        XCTAssertNil(session.state.context)
        XCTAssertEqual(session.framesRead, 1)
    }

    func testAConfirmedReadingOfTheCurrentFrameIsShown() throws {
        try liveSessionWithAReading(of: screenA, sender: "Maya")

        XCTAssertEqual(session.state.context?.sender, "Maya")
        XCTAssertEqual(session.state.context?.message, "Are we still on for 6?")
    }

    /// **The one that matters most.** The user switched conversation, so the
    /// frame the reading was taken from is not the frame on screen. The reading
    /// goes away rather than being offered against somebody else's message.
    func testASwitchedConversationRetiresTheReading() throws {
        try liveSessionWithAReading(of: screenA)
        XCTAssertNotNil(session.state.context)

        writer.recordFrame(screenB)
        step()

        XCTAssertEqual(session.state, .watching)
        XCTAssertNil(session.state.context, "a reading of the previous screen must not survive")
    }

    func testAPausedSessionIsPausedRatherThanLiveOrOff() throws {
        try liveSessionWithAReading(of: screenA)

        writer.setPaused(true)
        step()

        XCTAssertEqual(session.state, .paused)
        XCTAssertFalse(session.state.isLive, "no reading may be offered against a paused session")
        XCTAssertTrue(session.state.isVisible, "the user has to be told it stopped looking")
        XCTAssertNil(session.state.context)
    }

    /// **Frames stopping is not a pause, and it must not take the Reply button
    /// away.**
    ///
    /// `CaptureFreshness.frameWindow` is two seconds, and the rate it was
    /// justified against has never been measured (R1). If ReplayKit delivers on
    /// change rather than on a clock, a user reading a still conversation
    /// generates no frames at all — so the old code went `.paused` two seconds
    /// after they stopped scrolling, `isLive` went false, `canReply` went false,
    /// and the Reply button vanished from exactly the screen the feature exists
    /// for. Silently: the user cannot tell that from the feature being broken, and
    /// neither can we.
    ///
    /// The verdict is `.idle` and the strip keeps watching. The *reading* is still
    /// withdrawn, because nothing has confirmed the conversation on screen is the
    /// one that was read — a tap asks for a new one, and that tap is what answers
    /// the open question either way.
    func testAFrameGapKeepsTheOfferAndDropsTheReading() throws {
        let sessionID = writer.begin()
        let stale = CaptureClock.now() - CaptureClock.nanoseconds(3)
        writer.recordFrame(screenA, now: stale)
        try writer.publish(
            ScreenReadingRecord(
                sessionID: sessionID,
                requestSequence: 0,
                frameIdentity: screenA.identity,
                capturedAt: stale,
                readAt: stale,
                provenance: "cloud",
                sender: "Maya",
                message: "Are we still on for 6?",
                language: KeyboardLanguage.english.rawValue))
        writer.heartbeat()

        step()

        XCTAssertEqual(channel.verdict, .idle)
        XCTAssertEqual(session.state, .watching, "the offer stands; only the reading is withdrawn")
        XCTAssertTrue(session.state.isLive, "a live session with a quiet screen is still live")
        XCTAssertNil(session.state.context)
    }

    /// A jetsam kill at the memory limit fires no ReplayKit callback at all, so
    /// the only evidence is a heartbeat that stopped. It has to read as an
    /// ending with a way back, never as "screen context is off".
    func testAKilledProducerReadsAsStoppedUnexpectedly() {
        let tenSecondsAgo = CaptureClock.now() - CaptureClock.nanoseconds(10)
        writer.begin(now: tenSecondsAgo)
        writer.recordFrame(screenA, now: tenSecondsAgo)

        step()

        XCTAssertEqual(session.state, .ended(.lost))
        XCTAssertTrue(session.state.isVisible)
        XCTAssertFalse(session.state.isLive)
    }

    /// The other half of that rule. A page left behind by a session that died
    /// long ago is history, not news, and a strip still offering to restart it
    /// days later is crying wolf.
    func testAnEndingNobodyWatchedAndNobodyRemembersIsJustOff() {
        let longAgo = CaptureClock.now() - CaptureClock.nanoseconds(3_600)
        writer.begin(now: longAgo)
        writer.recordFrame(screenA, now: longAgo)

        step()

        XCTAssertEqual(session.state, .off)
    }

    /// …unless this consumer watched that same session run, in which case the
    /// ending is always news however long the wait was.
    func testAnEndingIsAlwaysNewsForASessionThisConsumerSawAlive() {
        writer.begin()
        writer.recordFrame(screenA)
        step()
        XCTAssertEqual(session.state, .watching)

        writer.end(.stopped, now: CaptureClock.now() - CaptureClock.nanoseconds(3_600))
        step()

        XCTAssertEqual(session.state, .ended(.stopped))
    }

    /// **A stop is reported, because nothing in this build knows who did it.**
    ///
    /// This used to assert the opposite: `.userStopped` read as `.off`, on the
    /// reasoning that the user did it on purpose so there was nothing to say.
    /// That reasoning needed the extension to know that, and it does not —
    /// `broadcastFinished()` takes no argument and carries no error, so the same
    /// mapping erased the strip when iOS ended a session for a call or the lock
    /// button. Redundant after a deliberate stop beats silent after an
    /// involuntary one.
    func testAStopIsReportedRatherThanHidden() {
        writer.begin()
        writer.recordFrame(screenA)
        step()

        writer.end(.stopped)
        step()

        XCTAssertEqual(session.state, .ended(.stopped))
        XCTAssertEqual(session.source, .capture)
    }

    func testAnEndingKeepsItsReason() {
        writer.begin()
        writer.recordFrame(screenA)
        step()

        writer.end(.lost)
        step()

        XCTAssertEqual(session.state, .ended(.lost))
    }

    // MARK: Reply

    func testReplyActsOnTheOfferedReading() async throws {
        try liveSessionWithAReading(of: screenA, sender: "Yusuf")

        let context = try await session.contextForReply()

        XCTAssertEqual(context.sender, "Yusuf")
        XCTAssertEqual(
            writer.intent()?.readNow, 0,
            "a reading that is already offerable does not need a new read")
    }

    /// Reply refuses a superseded reading rather than answering the wrong
    /// message, and it does not fall back to it when the new read never lands.
    func testReplyRefusesASupersededReadingAndAsksForAFreshOne() async throws {
        try liveSessionWithAReading(of: screenA, sender: "Maya")
        writer.recordFrame(screenB)
        step()

        do {
            let context = try await session.contextForReply(timeout: .milliseconds(600))
            XCTFail("expected a refusal, got a reply about \(context.sender)")
        } catch let error as AIEngineError {
            guard case .screenNotRead = error else {
                return XCTFail("unexpected error \(error)")
            }
        }

        XCTAssertEqual(writer.intent()?.readNow, 1, "the tap has to ask for a new read")
    }

    /// And when the new read does land, it is used — but only once it answers
    /// this tap and describes the frame on screen now.
    func testReplyWaitsForAReadingThatAnswersItsOwnTap() async throws {
        let sessionID = writer.begin()
        writer.recordFrame(screenB)
        step()

        async let reply = session.contextForReply(timeout: .seconds(5))

        try await Task.sleep(for: .milliseconds(300))
        let sequence = try XCTUnwrap(writer.intent()?.readNow)
        XCTAssertEqual(sequence, 1)

        let readAt = CaptureClock.now()
        try writer.publish(
            ScreenReadingRecord(
                sessionID: sessionID,
                requestSequence: sequence,
                frameIdentity: screenB.identity,
                capturedAt: readAt,
                readAt: readAt,
                provenance: "cloud",
                sender: "Daniel",
                message: "Anyone still merging into main?",
                language: KeyboardLanguage.english.rawValue))
        writer.recordFrame(screenB)

        let context = try await reply
        XCTAssertEqual(context.sender, "Daniel")
    }

    /// An answer to somebody else's tap is not an answer to this one.
    func testReplyIgnoresAReadingThatAnswersAnEarlierTap() async throws {
        let sessionID = writer.begin()
        writer.recordFrame(screenA)
        step()

        // A record left over from a previous request, of the frame on screen.
        let readAt = CaptureClock.now()
        try writer.publish(
            ScreenReadingRecord(
                sessionID: sessionID,
                requestSequence: 0,
                frameIdentity: screenA.identity,
                capturedAt: readAt,
                readAt: readAt,
                provenance: "cloud",
                sender: "Stale",
                message: "answered a tap ago",
                language: KeyboardLanguage.english.rawValue))
        writer.recordFrame(screenA)
        step()

        // It is offerable, so the strip may show it and the first check returns
        // it. Retire it, and the wait must not accept it again.
        XCTAssertEqual(session.state.context?.sender, "Stale")
        writer.recordFrame(screenB)
        step()

        do {
            let context = try await session.contextForReply(timeout: .milliseconds(600))
            XCTFail("expected a refusal, got a reply about \(context.sender)")
        } catch let error as AIEngineError {
            guard case .screenNotRead = error else {
                return XCTFail("unexpected error \(error)")
            }
        }
    }

    func testReplyStopsWaitingWhenTheSessionEnds() async throws {
        writer.begin()
        writer.recordFrame(screenA)
        step()

        async let reply = session.contextForReply(timeout: .seconds(5))
        try await Task.sleep(for: .milliseconds(300))
        writer.end(.stopped)

        do {
            let context = try await reply
            XCTFail("expected a refusal, got a reply about \(context.sender)")
        } catch let error as AIEngineError {
            guard case .screenNotRead(let reason) = error else {
                return XCTFail("unexpected error \(error)")
            }
            XCTAssertEqual(reason, ScreenContextEndReason.stopped.explanation)
        }
    }

    // MARK: The scripted demo yields

    /// The sample conversation is a demo and never outranks the truth: a real
    /// session takes the screen off it, and the counters that follow are the
    /// capture process's rather than the script's.
    func testARealSessionTakesTheScreenFromTheScriptedDemo() async throws {
        session.start()
        XCTAssertEqual(session.source, .scripted)

        writer.begin()
        writer.recordFrame(screenA)
        step()

        XCTAssertEqual(session.source, .capture)
        XCTAssertEqual(session.state, .watching)

        // Long enough for the script's own timeline to have reached its sample
        // reading and set the frame count to 34, had it survived.
        try await Task.sleep(for: .milliseconds(2_600))
        XCTAssertEqual(session.source, .capture)
        XCTAssertEqual(session.framesRead, 1)
        XCTAssertNil(session.state.context)
    }

    /// And with no producer at all, the demo is what the app shows.
    func testTheScriptedDemoSurvivesAnEmptyChannel() {
        session.start()

        step()

        XCTAssertEqual(session.source, .scripted)
        XCTAssertEqual(session.state, .starting)
    }

    /// A page left behind by a session that died long ago is not a live session
    /// and must not stop a sample the user has just started. Without this the
    /// demo lasts one poll on any phone with a stale channel.
    func testTheScriptedDemoSurvivesAPageLeftByADeadSession() {
        let longAgo = CaptureClock.now() - CaptureClock.nanoseconds(3_600)
        writer.begin(now: longAgo)
        writer.recordFrame(screenA, now: longAgo)
        step()
        XCTAssertEqual(session.state, .off)

        session.start()
        step()

        XCTAssertEqual(session.source, .scripted)
        XCTAssertEqual(session.state, .starting)
    }

    // MARK: The role contract

    /// **What `.observer` gates, and what it does not.**
    ///
    /// The doc comment used to say an observer "writes nothing", and the app
    /// falsified it: the app renders the whole `KeyboardView` — strip, Reply
    /// button and all — in `KeyboardPreview`, which onboarding and the Playground
    /// tab both use, so a Reply tap in the app raises the read sequence from a
    /// session started `as: .observer`. The contract is what changed. This pins
    /// both halves of the one that replaced it: the visibility flag is the
    /// keyboard's alone, because only the keyboard can claim it truthfully, and a
    /// read request is the user's own tap on Reply whichever process drew the
    /// button.
    func testAnObserverNeverClaimsTheKeyboardIsVisibleButMayStillAskForARead() {
        // The keyboard session `setUp` started owns the flag, so it is put away
        // first: what is under test is the app's session, alone on the page.
        session.stopConsuming()
        let app = ScreenContextChannel(reader: CaptureChannelReader(directory: directory))
        let appSession = ScreenContextSession()
        defer { appSession.stopConsuming() }
        writer.begin()
        writer.recordFrame(screenA)

        appSession.startConsuming(app, as: .observer)

        XCTAssertEqual(
            writer.intent()?.keyboardVisible, 0,
            "an app claiming the keyboard is visible would make the producer believe one that is not there")

        let sequence = app.requestRead()

        XCTAssertEqual(sequence, 1)
        XCTAssertEqual(
            writer.intent()?.readNow, 1,
            "the app hosts the same Reply button, and refusing its tap would make Reply do nothing there")
        XCTAssertEqual(writer.intent()?.keyboardVisible, 0, "and still not claim to be a keyboard")
    }

    func testTheKeyboardRoleIsTheOneThatWritesVisibility() {
        XCTAssertEqual(writer.intent()?.keyboardVisible, 1, "set by the session started in setUp")

        session.stopConsuming()

        XCTAssertEqual(writer.intent()?.keyboardVisible, 0)
    }

    // MARK: The sample is not overruled by a session that is not watching

    /// **The sample button looked like it did nothing, and this is why.**
    ///
    /// The guard that kept a running sample on screen lived in `publishAbsence`,
    /// so it covered `.off` and missed the two states any phone that has ever run
    /// a broadcast is in: paused, and ended inside the ten-minute window in which
    /// an ending is still worth showing. Either one overwrote the sample within
    /// one 250 ms poll and cancelled its task.
    func testAPausedSessionDoesNotTakeTheScreenFromTheSample() async throws {
        writer.begin()
        writer.recordFrame(screenA)
        writer.setPaused(true)
        step()
        XCTAssertEqual(session.state, .paused)

        session.start()
        XCTAssertEqual(session.source, .scripted)
        step()

        XCTAssertEqual(session.source, .scripted, "one poll used to be enough to kill the sample")
        try await Task.sleep(for: .milliseconds(2_600))
        XCTAssertEqual(session.source, .scripted, "and the script's own task used to be cancelled with it")
        XCTAssertNotNil(session.state.context, "the sample reached its message")
    }

    func testARecentlyEndedSessionDoesNotTakeTheScreenFromTheSample() {
        writer.begin()
        writer.recordFrame(screenA)
        step()
        writer.end(.stopped)
        step()
        XCTAssertEqual(session.state, .ended(.stopped))

        session.start()
        step()

        XCTAssertEqual(session.source, .scripted)
        XCTAssertEqual(session.state, .starting)
    }

    /// The half that is not negotiable. A session that is actually watching takes
    /// the screen back, because a made-up message must never sit on top of a real
    /// one with a red dot beside it.
    func testALiveSessionStillTakesTheScreenFromTheSample() {
        session.start()
        XCTAssertEqual(session.source, .scripted)

        writer.begin()
        writer.recordFrame(screenA)
        step()

        XCTAssertEqual(session.source, .capture)
    }

    /// The other half of the same button: while a session *is* watching, the
    /// sample is refused rather than silently ignored, and the screen that offers
    /// it renders `canPlaySample` as a sentence.
    func testTheSampleIsRefusedWhileASessionIsWatchingAndPermittedWhenItIsNot() {
        writer.begin()
        writer.recordFrame(screenA)
        step()
        XCTAssertFalse(session.canPlaySample)

        session.start()
        XCTAssertEqual(session.source, .capture, "the sample must not paint over a live session")
        XCTAssertNil(session.state.context)

        writer.setPaused(true)
        step()
        XCTAssertTrue(session.canPlaySample, "a session that is not looking has nothing to paint over")

        session.start()
        XCTAssertEqual(session.source, .scripted)
    }

    // MARK: What a tap nobody answers is told

    /// **The keyboard used to blame the wrong thing.** Reading inside the capture
    /// process is not built, so a Reply tap on a device raises the request and
    /// waits; the message the user got named a stale reading, which is a
    /// different failure with a different thing to do about it.
    func testAnUnansweredReadSaysNothingAnsweredRatherThanBlamingAStaleReading() async throws {
        writer.begin()
        writer.recordFrame(screenA)
        step()
        XCTAssertFalse(session.lastReadWentUnanswered)

        do {
            _ = try await session.contextForReply(timeout: .milliseconds(600))
            XCTFail("expected a refusal")
        } catch let error as AIEngineError {
            XCTAssertEqual(
                error.message,
                "Screen context is watching, but nothing answered the request to read the screen.")
            XCTAssertFalse(
                error.message.contains("what's on screen now"),
                "the old wording blamed the freshness gate for a request nothing answered")
        }

        XCTAssertTrue(
            session.lastReadWentUnanswered,
            "the strip and the AI menu stop offering a read the build has just failed to do")
    }

    func testAnAnsweredReadClearsTheUnansweredFlag() async throws {
        writer.begin()
        writer.recordFrame(screenA)
        step()
        _ = try? await session.contextForReply(timeout: .milliseconds(400))
        XCTAssertTrue(session.lastReadWentUnanswered)

        try liveSessionWithAReading(of: screenB, sender: "Maya", sequence: 9)
        _ = try await session.contextForReply(timeout: .milliseconds(400))

        XCTAssertFalse(session.lastReadWentUnanswered)
    }

    /// A new broadcast is a new chance: what the last one failed to answer says
    /// nothing about this one.
    func testANewSessionClearsTheUnansweredFlag() async throws {
        writer.begin()
        writer.recordFrame(screenA)
        step()
        _ = try? await session.contextForReply(timeout: .milliseconds(400))
        XCTAssertTrue(session.lastReadWentUnanswered)

        writer.begin()
        writer.recordFrame(screenA)
        step()

        XCTAssertFalse(session.lastReadWentUnanswered)
    }

    // MARK: The secure-field guard leaves a number behind

    /// The guard itself is a truth table and `SecureFieldTests` is where it is
    /// checked. What is checked here is the half that cannot be pure: a refusal
    /// has to leave a count in the page the keyboard owns, or the open question
    /// underneath the whole guard — whether any host answers `isSecureTextEntry`
    /// through a proxy at all — stays folklore instead of becoming a number a
    /// device run can be read against.
    func testARefusedReadIsCountedAndNoReadIsRequested() {
        writer.begin()
        writer.recordFrame(screenA)
        step()

        XCTAssertFalse(session.permitsRead(secure: true, contentType: nil))
        XCTAssertFalse(session.permitsRead(secure: false, contentType: .some(.password)))
        // Silence permits: iOS never shows this keyboard for a secure field, and
        // nil is an unimplemented optional trait, not a password field. It is
        // still counted as unanswered, which is the whole point of the field.
        XCTAssertTrue(session.permitsRead(secure: nil, contentType: nil))
        XCTAssertTrue(session.permitsRead(secure: false, contentType: nil))
        // Silent *and* refused: a sensitive content type still bites.
        XCTAssertFalse(session.permitsRead(secure: nil, contentType: .some(.password)))

        let intent = writer.intent()
        XCTAssertEqual(
            intent?.refusedSecure, 3,
            "outright, by content type, and by content type on a silent field")
        XCTAssertEqual(
            intent?.refusedSecureUnknown, 2,
            "every decision where the host stayed silent, permitted or not")
        XCTAssertEqual(intent?.readNow, 0, "a refused tap must not reach the capture process")
    }

    // MARK: A page from a previous run

    /// **Nothing a previous run left behind may be shown as current**, and the
    /// two ways a page goes stale are not the same: an ordinary one where time
    /// has passed, and a reboot, after which `CLOCK_MONOTONIC_RAW` has restarted
    /// *below* every timestamp in the page. `CaptureClock.elapsed` reports a
    /// future timestamp as infinitely old for exactly this case.
    func testAPageAndAReadingLeftByAPreviousRunShowNothing() throws {
        let longAgo = CaptureClock.now() - CaptureClock.nanoseconds(3_600)
        let sessionID = writer.begin(now: longAgo)
        writer.recordFrame(screenA, now: longAgo)
        try writer.publish(
            ScreenReadingRecord(
                sessionID: sessionID,
                requestSequence: 1,
                frameIdentity: screenA.identity,
                capturedAt: longAgo,
                readAt: longAgo,
                provenance: "cloud",
                sender: "Maya",
                message: "Are we still on for 6?",
                language: KeyboardLanguage.english.rawValue))

        step()

        XCTAssertEqual(session.state, .off)
        XCTAssertNil(session.state.context, "an hour-old reading is not what is on screen now")
    }

    func testAPageFromBeforeARebootShowsNothing() throws {
        // A reboot restarts the monotonic clock, so yesterday's page carries
        // timestamps in this boot's future.
        let afterReboot = CaptureClock.now() + CaptureClock.nanoseconds(86_400)
        let sessionID = writer.begin(now: afterReboot)
        writer.recordFrame(screenA, now: afterReboot)
        try writer.publish(
            ScreenReadingRecord(
                sessionID: sessionID,
                requestSequence: 1,
                frameIdentity: screenA.identity,
                capturedAt: afterReboot,
                readAt: afterReboot,
                provenance: "cloud",
                sender: "Maya",
                message: "Are we still on for 6?",
                language: KeyboardLanguage.english.rawValue))

        step()

        XCTAssertEqual(session.state, .off)
        XCTAssertNil(session.state.context)
    }

    /// **A cancelled Reply must stop polling.**
    ///
    /// `contextForReply` waits for a fresh reading by sleeping between polls.
    /// While it swallowed the cancellation with `try?`, `Task.sleep` returned
    /// immediately and the only thing left pacing the loop was the deadline:
    /// measured at 31,588 polls in two seconds against six in the healthy case,
    /// each one a file read, a JSON decode and a SwiftUI invalidation on the main
    /// actor, in a process capped near 48 MB.
    ///
    /// It is the ordinary path, not an unlucky one. `beginWork` cancels the
    /// previous task on every new action, the strip's Reply button stays hittable
    /// while a result panel is up, and until the capture process runs a reader
    /// every Reply times out, so "nothing happened, tap it again" is what a user
    /// does.
    func testACancelledReplyStopsPollingTheChannel() async throws {
        writer.begin()
        writer.heartbeat()
        // Live, but nothing offerable ever arrives: the wait loop's `continue`
        // branch, which is where the runaway lived.
        writer.recordFrame(screenA)

        var polls = 0
        let counting = channel.$verdict.sink { _ in polls += 1 }
        defer { counting.cancel() }

        let waiting = Task { try await session.contextForReply(timeout: .seconds(12)) }
        try await Task.sleep(for: .milliseconds(300))
        waiting.cancel()

        let atCancel = polls
        try await Task.sleep(for: .seconds(1))

        XCTAssertLessThan(
            polls - atCancel, 20,
            "the wait loop kept polling after cancellation: \(polls - atCancel) polls in one second")
    }

    // MARK: A read that answered and failed

    /// **A failure must end the wait, not run out the clock.**
    ///
    /// The capture process publishes an outcome for every read it attempts, and
    /// the freshness gate deliberately refuses to call a non-`.read` record
    /// offerable. Before this, that combination meant a published failure was
    /// invisible: `contextForReply` only ever acted on `.offerable`, so a "no
    /// backend configured" answer sat in the container while the user waited the
    /// full twelve seconds and was then told nothing answered — the wrong reason
    /// as well as a slow one.
    func testAPublishedFailureEndsTheWaitWithItsOwnReason() async throws {
        writer.begin()
        writer.heartbeat()
        writer.recordFrame(screenA)
        step()

        let waiting = Task { try await session.contextForReply(timeout: .seconds(6)) }
        try await Task.sleep(for: .milliseconds(250))

        let sequence = try XCTUnwrap(writer.intent()?.readNow)
        XCTAssertGreaterThan(sequence, 0, "the tap must have raised a request")
        try writer.publish(
            ScreenReadingRecord(
                sessionID: try XCTUnwrap(writer.status()?.sessionID),
                requestSequence: sequence,
                frameIdentity: screenA.identity,
                capturedAt: CaptureClock.now(), readAt: CaptureClock.now(),
                provenance: "cloud",
                outcome: .failed, detail: "No cloud model is configured.",
                sender: "", message: "", language: ""))

        do {
            _ = try await waiting.value
            XCTFail("a failed read must not be returned as a reading")
        } catch AIEngineError.screenNotRead(let reason) {
            XCTAssertEqual(reason, "No cloud model is configured.")
        }
        XCTAssertFalse(
            session.lastReadWentUnanswered,
            "something did answer, so the strip must not say nothing did")
    }

    /// Nothing to reply to is an answer, and must not read as a fault.
    func testNothingToReplyToEndsTheWaitWithoutSoundingLikeAnError() async throws {
        writer.begin()
        writer.heartbeat()
        writer.recordFrame(screenA)
        step()

        let waiting = Task { try await session.contextForReply(timeout: .seconds(6)) }
        try await Task.sleep(for: .milliseconds(250))

        let sequence = try XCTUnwrap(writer.intent()?.readNow)
        try writer.publish(
            ScreenReadingRecord(
                sessionID: try XCTUnwrap(writer.status()?.sessionID),
                requestSequence: sequence,
                frameIdentity: screenA.identity,
                capturedAt: CaptureClock.now(), readAt: CaptureClock.now(),
                provenance: "cloud",
                outcome: .nothing, detail: "",
                sender: "", message: "", language: ""))

        do {
            _ = try await waiting.value
            XCTFail("nothing to reply to is not a reading")
        } catch AIEngineError.screenNotRead(let reason) {
            XCTAssertEqual(reason, "There is no message on this screen to reply to.")
        }
    }


    /// **The playground must not photograph the playground.**
    ///
    /// The app hosts a real `KeyboardView` in its Playground tab and in
    /// onboarding, so its Reply button is the same button. As an observer it may
    /// watch the page, but a read raised from there would capture *this app* —
    /// our own preview, with our own animation inside the fingerprint band — and
    /// answer a question nobody asked. The scripted sample is what that screen is
    /// for and is served before this check; anything else is refused in words.
    func testAnObserverRefusesToReadRatherThanPhotographTheApp() async throws {
        writer.begin()
        writer.heartbeat()
        writer.recordFrame(screenA)

        let observing = ScreenContextSession()
        observing.startConsuming(
            ScreenContextChannel(reader: CaptureChannelReader(directory: directory)),
            as: .observer)
        defer { observing.stopConsuming() }

        do {
            _ = try await observing.contextForReply(timeout: .seconds(2))
            XCTFail("an observer must not raise a read of the app's own screen")
        } catch AIEngineError.screenNotRead(let reason) {
            XCTAssertTrue(reason.contains("in the keyboard"), reason)
        }
        XCTAssertEqual(
            writer.intent()?.readNow, 0,
            "and it must not have reached the capture process at all")
    }

}
