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

        writer.end(.phoneCall, now: CaptureClock.now() - CaptureClock.nanoseconds(3_600))
        step()

        XCTAssertEqual(session.state, .ended(.phoneCall))
    }

    /// The user stopping it is not an ending to report. There is nothing to
    /// explain and nothing to restart: they did it on purpose.
    func testTheUserStoppingReadsAsOff() {
        writer.begin()
        writer.recordFrame(screenA)
        step()

        writer.end(.userStopped)
        step()

        XCTAssertEqual(session.state, .off)
        XCTAssertEqual(session.source, .none)
    }

    func testAnEndingKeepsItsReason() {
        writer.begin()
        writer.recordFrame(screenA)
        step()

        writer.end(.deviceLocked)
        step()

        XCTAssertEqual(session.state, .ended(.deviceLocked))
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
        writer.end(.phoneCall)

        do {
            let context = try await reply
            XCTFail("expected a refusal, got a reply about \(context.sender)")
        } catch let error as AIEngineError {
            guard case .screenNotRead(let reason) = error else {
                return XCTFail("unexpected error \(error)")
            }
            XCTAssertEqual(reason, ScreenContextEndReason.phoneCall.explanation)
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
}
