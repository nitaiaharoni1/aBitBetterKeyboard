import Foundation
import XCTest

@testable import AIKeyboardCore

/// Session-ending, withdrawal, and reconfiguration tests extracted from
/// `ScreenContextConsumerTests`.
///
/// Uses the same real-channel fixture (no mocks below the session) as the
/// parent suite; setUp/tearDown are duplicated here rather than inherited
/// because the ending tests do not need `liveSessionWithAReading`.
@MainActor
final class ScreenContextSessionEndTests: XCTestCase {

    private var directory: URL!
    private var writer: CaptureChannelWriter!
    private var channel: ScreenContextChannel!
    private var session: ScreenContextSession!

    private let screenA = FrameFingerprint(
        identity: FrameIdentity(w0: 11, w1: 12, w2: 13, w3: 14), settleHash: 0xA)

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

    // MARK: Session endings

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

    /// **A session that ended without ever receiving a frame is a different
    /// sentence, and it used to be the same one.**
    ///
    /// This is the shape a device reported: screen context switched on, the strip
    /// says "Screen context stopped. Restart it in AI Keyboard.", and nothing
    /// anywhere says which half broke. `broadcastFinished()` carries no reason, but
    /// the producer knows whether ReplayKit ever handed it anything — R1, and the
    /// single most likely way this pipeline runs and does nothing.
    ///
    /// **The ending is taken from `ScreenContextEndReason.ending`, not written by
    /// hand**, and that is the difference between this test and the one it
    /// replaced. Naming `.noFrames` in the test body would have left a
    /// `SampleHandler` that still wrote `.stopped` unconditionally passing a test
    /// about it not doing that. Driving the same function the producer drives, from
    /// the same counter the producer reads, is what makes the assertion capable of
    /// failing.
    func testASessionThatNeverGotAFrameSaysSoRatherThanJustStopping() throws {
        writer.begin()
        step()
        XCTAssertEqual(session.state, .starting, "a session with no frame yet is still starting")

        let delivered = try XCTUnwrap(writer.status()).framesDelivered
        XCTAssertEqual(delivered, 0, "the page has to agree that no frame arrived")
        writer.end(ScreenContextEndReason.ending(framesDelivered: delivered))
        step()

        XCTAssertEqual(session.state, .ended(.noFrames))
        XCTAssertNotEqual(
            ScreenContextEndReason.noFrames.explanation,
            ScreenContextEndReason.stopped.explanation,
            "the two endings must not read the same, or the diagnosis is not one")
    }

    /// The other side of the same decision: a session that *did* receive frames
    /// ends as an ordinary stop and claims no cause.
    func testASessionThatSawFramesEndsAsAnOrdinaryStop() throws {
        writer.begin()
        writer.recordFrame(screenA)
        step()

        let delivered = try XCTUnwrap(writer.status()).framesDelivered
        XCTAssertGreaterThan(delivered, 0)
        writer.end(ScreenContextEndReason.ending(framesDelivered: delivered))
        step()

        XCTAssertEqual(session.state, .ended(.stopped))
    }

    /// A broadcast with no screen reader behind it is refused at the start, and the
    /// refusal is what the keyboard shows — with the fix, and without a restart it
    /// would only repeat.
    ///
    /// The reason comes from `refusalToStart`, so a producer that stopped refusing
    /// fails this rather than passing it.
    func testASessionWithNoReaderIsReportedAsUnconfigured() throws {
        writer.begin()
        let refusal = try XCTUnwrap(
            ScreenContextEndReason.refusalToStart(canRead: false),
            "a session with no reader has to be refused")
        writer.end(refusal)
        step()

        XCTAssertEqual(session.state, .ended(.notConfigured))
        guard case .ended(let reason) = session.state else { return XCTFail("not an ending") }
        XCTAssertFalse(
            reason.canRestart,
            "offering a restart here starts a broadcast that ends the same way in a second")
    }

    /// **A failure about the setup withdraws the offer; a failure about the moment
    /// does not.**
    ///
    /// Both branches used to clear the flag, so after the screen-reading server
    /// rejected the access token the strip went straight back to "Reply can read
    /// this screen" — and the next tap uploaded another picture of the user's
    /// screen to be refused in exactly the same way. The broken version returns
    /// `false` for the first case below.
    func testARejectedTokenWithdrawsTheOfferAndANetworkBlipDoesNot() async throws {
        for (detail, withdraws) in [
            (ScreenReadService.tokenRejected, true),
            (ScreenReadService.addressNotAServer, true),
            ("The backend is unreachable.", false)
        ] {
            let sessionID = writer.begin()
            writer.recordFrame(screenA)
            step()

            async let reply = session.contextForReply(timeout: .seconds(5))
            try await Task.sleep(for: .milliseconds(250))
            try writer.publish(
                ScreenReadingRecord(
                    sessionID: sessionID,
                    requestSequence: channel.requestSequence,
                    frameIdentity: screenA.identity,
                    capturedAt: CaptureClock.now(),
                    readAt: CaptureClock.now(),
                    provenance: "cloud",
                    outcome: .failed,
                    detail: detail,
                    sender: "", message: "", language: ""))

            do {
                _ = try await reply
                XCTFail("expected a refusal for \(detail)")
            } catch let error as AIEngineError {
                guard case .screenNotRead(let shown) = error else {
                    return XCTFail("unexpected error \(error)")
                }
                XCTAssertEqual(shown, detail, "the strip must show the server's own reason")
            }

            XCTAssertEqual(
                session.lastReadWentUnanswered, withdraws,
                withdraws
                    ? "a failure that repeats must stop the strip promising a read"
                    : "a one-off failure must not withdraw the offer")
        }
    }

    /// **A `.notConfigured` ending is retired the moment a backend is set.**
    ///
    /// Without this the Screen Context screen printed "Screen context can't run
    /// yet" for ten minutes after the user fixed exactly that, while the card
    /// below it said "Saved. Screen context can start." — and the keyboard
    /// withheld the picker for the same window, so the broadcast that would have
    /// cleared the page could not be started. The broken version reports the
    /// ending in both halves below.
    func testAnUnconfiguredEndingStopsBeingNewsOnceABackendIsSet() throws {
        session.isScreenReadingConfigured = { false }
        writer.begin()
        writer.end(try XCTUnwrap(ScreenContextEndReason.refusalToStart(canRead: false)))
        step()
        XCTAssertEqual(
            session.state, .ended(.notConfigured),
            "with no backend the ending is exactly what the user needs to see")

        session.isScreenReadingConfigured = { true }
        step()
        XCTAssertEqual(
            session.state, .off,
            "the ending names a cause the user has just removed")

        session.isScreenReadingConfigured = { true }
        writer.begin()
        writer.end(.noFrames)
        step()
        XCTAssertEqual(session.state, .ended(.noFrames))
    }

    /// The wait on Reply ends with the ending's own words, whichever ending it is.
    ///
    /// **This one pins a path rather than a change**, and it is worth saying so:
    /// `contextForReply` already threw `reason.explanation` before any of this, so
    /// nothing in the producer's diff could break it. What it does catch is a
    /// future `.ended` mapping that collapses the new reasons back into one
    /// sentence on the way to the user.
    func testReplyStopsWaitingWithTheReasonTheProducerRecorded() async throws {
        writer.begin()
        writer.recordFrame(screenA)
        step()

        async let reply = session.contextForReply(timeout: .seconds(5))
        try await Task.sleep(for: .milliseconds(300))
        writer.end(.noFrames)

        do {
            let context = try await reply
            XCTFail("expected a refusal, got a reply about \(context.sender)")
        } catch let error as AIEngineError {
            guard case .screenNotRead(let reason) = error else {
                return XCTFail("unexpected error \(error)")
            }
            XCTAssertEqual(reason, ScreenContextEndReason.noFrames.explanation)
        }
    }
}
// Scripted-demo, role-contract, and sample-guard tests live in ScreenContextDemoTests.swift.
// Reply tests live in ScreenContextReplyTests.swift.
// Unanswered-read, secure-field, previous-run, and failure-path tests live in ScreenContextReadTests.swift.
