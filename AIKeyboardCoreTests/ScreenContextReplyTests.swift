import Foundation
import XCTest

@testable import AIKeyboardCore

/// Reply-path tests extracted from `ScreenContextConsumerTests`.
/// Fixture is identical: same real channel, real mmap'd pages, no mocks below the session.
@MainActor
final class ScreenContextReplyTests: XCTestCase {

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
}
