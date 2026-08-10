import Foundation
import XCTest

@testable import AIKeyboardCore

/// Scripted-demo, role-contract, and sample-guard tests extracted from
/// `ScreenContextConsumerTests`. Same real fixture.
@MainActor
final class ScreenContextDemoTests: XCTestCase {

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

    private func step() {
        channel.poll()
    }

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
        writer.recordFrame(screen)
        step()
        return sessionID
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
}
