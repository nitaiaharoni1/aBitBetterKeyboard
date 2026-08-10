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
        // **Injected, because the default answer stopped being nil.**
        // `isScreenReadingConfigured` defaults to
        // `BackendTransport.configured() != nil`, and once a `bundledDefaultURL`
        // shipped that is true on every install — so `isWorthReporting` retired
        // `.notConfigured` before this suite could observe it and
        // `testASessionWithNoReaderIsReportedAsUnconfigured` failed against a
        // session that was behaving correctly. The seam is a `var` closure for
        // exactly this; the suite simply was not using it, so the test's outcome
        // depended on whether a backend happened to be reachable.
        session.isScreenReadingConfigured = { false }
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

}
// Session-ending, withdrawal, and reconfiguration tests live in ScreenContextSessionEndTests.swift.
// Reply tests live in ScreenContextReplyTests.swift.
// Scripted-demo, role-contract, and sample-guard tests live in ScreenContextDemoTests.swift.
// Unanswered-read, secure-field, previous-run, and failure-path tests live in ScreenContextReadTests.swift.
