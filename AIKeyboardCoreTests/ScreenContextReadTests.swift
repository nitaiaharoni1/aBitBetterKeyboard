import Foundation
import XCTest

@testable import AIKeyboardCore

/// Unanswered-read, secure-field, previous-run, and failure-path tests extracted
/// from `ScreenContextConsumerTests`. Same real fixture.
@MainActor
final class ScreenContextReadTests: XCTestCase {

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
        // **`permitsRead` writes outside this scratch directory now, and this is
        // what stops the suite leaving it behind.** Since NIT-187 every decision
        // is counted into `SecureDecisionRecord` as well as into the channel
        // page, and that record lives in the App Group container — which the
        // simulator hands this target for real, entitlement or not, as
        // `KeyboardMemoryPeakTests` records. Without this, running the suite
        // leaves a "Reply and secure fields" row in the simulator's own Settings
        // describing taps nobody made. Same family as the suite teaching
        // `PersonalLanguageModel` the word `Handi` ten times, and the reason
        // every other record's tests take an explicit URL instead.
        //
        // The write is dispatched, so it is drained first: `note(_:)` uses one
        // serial queue and a barrier-free `sync` on it returns only after every
        // block queued before it has run.
        removeSecureDecisionRecord()
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

    // MARK: What a tap nobody answers is told

    /// **The keyboard used to blame the wrong thing.**
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

    /// **Nothing a previous run left behind may be shown as current.**
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
