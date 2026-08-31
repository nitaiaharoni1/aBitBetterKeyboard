import Foundation
import XCTest

@testable import AIKeyboardCore
@testable import AIKeyboardShared

/// The read, driven the way the capture process drives it.
///
/// Nothing below the network is faked: a real `CaptureChannelWriter` and a real
/// `CaptureChannelReader` on a real mmap'd page, the real `CloudScreenReader`
/// with its real prompt and its real parsing, and a transport that answers with
/// what the test says instead of calling a backend. Only the container is
/// swapped for a temporary directory, because this target carries no App Group
/// entitlement.
///
/// **What it cannot cover, and does not pretend to.** No frame arrives here.
/// The iOS Simulator runtime ships no `replayd`, so no broadcast session starts
/// on this destination, `SampleHandler` is never called and `FrameScaler` never
/// sees a `CVPixelBuffer`. These tests hand the service the bytes a frame would
/// have become. That the frame *arrives*, in what pixel format, at what size,
/// and whether the process survives its ~50 MB cap while a TLS connection is
/// open, are all device measurements and none has been taken.
final class ScreenReadServiceTests: XCTestCase {

    private var directory: URL!
    private var writer: CaptureChannelWriter!
    private var keyboard: CaptureChannelReader!
    private var session: UUID!

    private let screen = FrameFingerprint(
        identity: FrameIdentity(w0: 11, w1: 12, w2: 13, w3: 14), settleHash: 0xA)
    private let otherScreen = FrameFingerprint(
        identity: FrameIdentity(w0: 21, w1: 22, w2: 23, w3: 24), settleHash: 0xB)

    /// Four bytes that start like a JPEG, so the "no pixels in the container"
    /// test is looking for something a real encode would also produce.
    private let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46])

    override func setUp() async throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("read-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        writer = try XCTUnwrap(CaptureChannelWriter(directory: directory))
        keyboard = CaptureChannelReader(directory: directory)
        session = writer.begin()
    }

    override func tearDown() async throws {
        writer = nil
        keyboard = nil
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: Helpers

    private func service(_ transport: (any CloudTransport)?) -> ScreenReadService {
        let service = ScreenReadService(
            channel: writer, reader: transport.map { CloudScreenReader(transport: $0) })
        service.begin(session: session, intent: writer.intent())
        return service
    }

    /// The user tapping Reply: the keyboard raises the sequence in its own page.
    @discardableResult
    private func tapReply() -> UInt64 { keyboard.requestRead() }

    /// One sampled frame, offered to the service the way the delivery callback
    /// offers it.
    @discardableResult
    private func sample(
        _ service: ScreenReadService, showing frame: FrameFingerprint,
        at capturedAt: UInt64 = CaptureClock.now()
    ) -> ScreenReadService.Ticket? {
        writer.recordFrame(frame, now: capturedAt)
        guard
            let ticket = service.claim(
                intent: writer.intent(), identity: frame.identity, capturedAt: capturedAt)
        else { return nil }
        service.start(ticket, jpeg: jpeg)
        return ticket
    }

    /// The record answering `sequence`. Polls the way the keyboard polls, because
    /// the read is off this thread by construction.
    ///
    /// Fails rather than skips when nothing arrives. Silence is the failure this
    /// whole class exists to remove, so a test that cannot find a record has
    /// found the bug rather than an inconvenience.
    private func record(
        answering sequence: UInt64, timeout: Duration = .seconds(5)
    ) async throws
        -> ScreenReadingRecord
    {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if let record = keyboard.reading(), record.requestSequence >= sequence { return record }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("nothing answered request \(sequence) within \(timeout)")
        throw CocoaError(.fileNoSuchFile)
    }

    private func status() throws -> CaptureStatus {
        try XCTUnwrap(keyboard.status().status)
    }

    // MARK: The trigger

    /// The rule the whole privacy argument rests on: frames arrive at up to 60 a
    /// second and none of them is a reason to read. Only a tap is.
    func testAFrameOnItsOwnNeverStartsARead() {
        let transport = FakeTransport(answer: ["sender": "Maya", "message": "hi"])
        let service = service(transport)

        for _ in 0..<10 {
            XCTAssertNil(sample(service, showing: screen))
        }

        XCTAssertEqual(transport.calls, 0)
        XCTAssertNil(keyboard.reading())
    }

    func testATapIsAnsweredOnceAndOnlyOnce() async throws {
        let transport = FakeTransport(answer: ["sender": "Maya", "message": "Are we still on?"])
        let service = service(transport)

        let sequence = tapReply()
        XCTAssertNotNil(sample(service, showing: screen))
        _ = try await record(answering: sequence)

        // Every later frame sees the same sequence in the page and does nothing
        // with it. A read per frame would be a read every 250 ms.
        for _ in 0..<10 {
            XCTAssertNil(sample(service, showing: screen))
        }
        XCTAssertEqual(transport.calls, 1)
    }

    /// The record has to carry the sequence the keyboard is waiting on *and* the
    /// identity of the frame that was actually read: the first is how it knows
    /// the answer is its own, the second is the only thing standing between the
    /// user and a reply about a conversation they have left.
    func testTheRecordCarriesTheRequestAndTheFrameItRead() async throws {
        let transport = FakeTransport(answer: [
            "sender": "Maya", "message": "מתי אתה מגיע?", "language": "hebrew"
        ])
        let service = service(transport)

        let sequence = tapReply()
        let capturedAt = CaptureClock.now()
        let ticket = try XCTUnwrap(sample(service, showing: screen, at: capturedAt))
        XCTAssertEqual(ticket.sequence, sequence)

        let record = try await record(answering: sequence)
        XCTAssertEqual(record.requestSequence, sequence)
        XCTAssertEqual(record.frameIdentity, screen.identity)
        XCTAssertNotEqual(record.frameIdentity, otherScreen.identity)
        XCTAssertEqual(record.sessionID, session)
        XCTAssertEqual(record.capturedAt, capturedAt)
        XCTAssertGreaterThanOrEqual(record.readAt, record.capturedAt)
        XCTAssertEqual(record.outcome, .read)
        XCTAssertEqual(record.sender, "Maya")
        XCTAssertEqual(record.message, "מתי אתה מגיע?")
        XCTAssertEqual(record.language, KeyboardLanguage.hebrew.rawValue)
        XCTAssertEqual(record.provenance, "cloud")

        // The bytes the delivery callback encoded are the bytes that went out,
        // under the prompt `Bar/screen-context/` scores. The capture process gets
        // no second copy of either.
        let sent = try XCTUnwrap(transport.requests.first)
        guard case .screenJPEG(let sentJPEG) = sent.payload else {
            XCTFail("screen reading must use the screen JPEG payload")
            return
        }
        XCTAssertEqual(sentJPEG, jpeg)
        XCTAssertEqual(sent.instructions, ScreenPrompt.instructions)
        XCTAssertEqual(sent.fields.map(\.name), ScreenPrompt.fields.map(\.name))
    }

    /// A read takes about five seconds and the user can tap again inside it. The
    /// second tap must not open a second connection: the container holds one
    /// `reading.json`, so a second read would have nowhere to put its answer that
    /// did not overwrite the first.
    func testASecondTapDuringAReadDoesNotStartASecondRead() async throws {
        let transport = FakeTransport(answer: ["sender": "Maya", "message": "hi"])
        transport.holdOpen = true
        let service = service(transport)

        let first = tapReply()
        XCTAssertNotNil(sample(service, showing: screen))
        try await transport.waitUntilCalled()

        let second = tapReply()
        XCTAssertNil(
            sample(service, showing: screen), "a read is already in flight; this must not start one")
        XCTAssertEqual(transport.calls, 1)

        await transport.release()

        // The in-flight read answers the newer tap too, so the keyboard waiting
        // on it stops waiting rather than timing out.
        let record = try await record(answering: second)
        XCTAssertEqual(record.requestSequence, second)
        XCTAssertGreaterThan(second, first)
        XCTAssertEqual(transport.calls, 1)
        XCTAssertEqual(try status().refusedInFlight, 1)
    }

    /// **The same second tap, one conversation later, must not be swallowed.**
    ///
    /// The fold above is right because both taps are about one screen: the answer
    /// already coming back answers both. It is wrong the moment the user leaves
    /// that conversation, and five seconds of cloud latency is plenty of time to.
    /// The running read will publish a record describing the screen they walked
    /// away from, `CaptureFreshness` will refuse it, and the tap has to survive
    /// that and be served for real.
    ///
    /// It used to die there instead. `claim` marked every request seen before it
    /// checked whether it could serve one, so once the fold had bumped `seen`
    /// past this tap no later frame could satisfy `readNow > seen`. The read
    /// finished, the gate refused it, and the keyboard sat out its full twelve
    /// seconds while frames of the new conversation went by unread — a Reply that
    /// did nothing, recoverable only by tapping a third time.
    func testATapAboutADifferentScreenIsServedAfterTheRunningReadRatherThanFolded()
        async throws
    {
        let transport = FakeTransport(answer: ["sender": "Maya", "message": "hi"])
        transport.holdOpen = true
        let service = service(transport)

        let first = tapReply()
        XCTAssertNotNil(sample(service, showing: screen))
        try await transport.waitUntilCalled()

        // The user leaves that conversation and taps Reply on another one.
        let second = tapReply()
        // Sampled repeatedly, because that is what really happens: the deferred
        // request is re-offered by every frame at 4 Hz until the running read
        // releases the flag. Each one must decline without consuming the request.
        for _ in 0..<4 {
            XCTAssertNil(
                sample(service, showing: otherScreen),
                "a read is still in flight, so this frame must not start a second one")
        }
        XCTAssertEqual(transport.calls, 1)
        XCTAssertEqual(
            try status().refusedInFlight, 0,
            "this is not a fold: nothing running answers a tap about another screen")

        transport.holdOpen = false
        await transport.release()

        // Waiting on the *first* sequence is what makes this deterministic: the
        // record only exists once `finish` has run, which is what clears the flag
        // the next claim depends on. It also pins the other half of the fix —
        // the running read stamps its own sequence, not the newer tap's, so the
        // keyboard is never handed a record it has to refuse.
        let stale = try await record(answering: first)
        XCTAssertEqual(stale.frameIdentity, screen.identity)

        // The next frame of the new conversation serves the tap that was waiting.
        let ticket = try XCTUnwrap(
            sample(service, showing: otherScreen),
            "the deferred tap has to be claimable once the running read finishes")
        XCTAssertEqual(ticket.sequence, second)
        XCTAssertEqual(ticket.identity, otherScreen.identity)

        let record = try await record(answering: second)
        XCTAssertEqual(record.requestSequence, second)
        XCTAssertEqual(
            record.frameIdentity, otherScreen.identity,
            "the answer describes the screen the user is actually looking at")
        XCTAssertEqual(transport.calls, 2, "two screens, two reads")
    }

    /// A request left in the page by a keyboard that stopped waiting a long time
    /// ago is not a request. Without this, a session starting an hour later reads
    /// whatever happens to be on screen and spends a cloud call on it.
    func testARequestOlderThanTheWindowIsNotServed() {
        let transport = FakeTransport(answer: ["sender": "Maya", "message": "hi"])
        let service = service(transport)

        let longAgo = CaptureClock.now() - ScreenReadService.requestWindow - 1
        keyboard.requestRead(now: longAgo)

        XCTAssertNil(sample(service, showing: screen))
        XCTAssertEqual(transport.calls, 0)
        XCTAssertNil(keyboard.reading())
    }

    /// The same rule from the other side: a tap raised before this session began
    /// belongs to the previous one.
    func testATapRaisedBeforeTheSessionStartedIsNotServed() {
        let transport = FakeTransport(answer: ["sender": "Maya", "message": "hi"])
        tapReply()

        let service = service(transport)

        XCTAssertNil(sample(service, showing: screen))
        XCTAssertEqual(transport.calls, 0)
    }

    // Answer, promise, and counter tests live in ScreenReadServiceAnswerTests.swift.
}

// FakeTransport lives in ScreenReadFakeTransport.swift.
