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
        XCTAssertEqual(sent.image?.data, jpeg)
        XCTAssertEqual(sent.image?.mimeType, "image/jpeg")
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

    // MARK: Answers that are not readings

    /// The model looked and there is nothing to answer — the newest incoming
    /// bubble is a voice note. That is an answer, and the keyboard has to be told
    /// so rather than waiting out twelve seconds for a reading that is not coming.
    func testAScreenWithNothingToReplyToIsAnsweredRatherThanIgnored() async throws {
        let service = service(FakeTransport(answer: ["sender": "", "message": ""]))

        let sequence = tapReply()
        XCTAssertNotNil(sample(service, showing: screen))

        let record = try await record(answering: sequence)
        XCTAssertEqual(record.outcome, .nothing)
        XCTAssertFalse(record.detail.isEmpty, "the strip needs a sentence to show")
        XCTAssertTrue(record.message.isEmpty)
    }

    func testAFailedReadPublishesTheReasonRatherThanNothing() async throws {
        let service = service(FakeTransport(failure: .network("The backend is unreachable.")))

        let sequence = tapReply()
        XCTAssertNotNil(sample(service, showing: screen))

        let record = try await record(answering: sequence)
        XCTAssertEqual(record.outcome, .failed)
        XCTAssertEqual(record.detail, "The backend is unreachable.")
        XCTAssertTrue(record.message.isEmpty)
    }

    /// No backend in this build. The tap is still answered, at the moment it is
    /// made, and no read is attempted.
    func testWithNoReaderConfiguredTheTapIsAnsweredImmediately() async throws {
        let service = service(nil)
        XCTAssertFalse(service.canRead)

        let sequence = tapReply()
        XCTAssertNil(sample(service, showing: screen))

        let record = try await record(answering: sequence)
        XCTAssertEqual(record.outcome, .failed)
        XCTAssertTrue(record.detail.contains("not set up"))
    }

    /// The frame could not be downscaled or encoded — `FrameScaler` returned nil
    /// for a pixel format it does not know. The claimed request is answered
    /// anyway, because the keyboard is already waiting on its sequence.
    func testAFrameThatCouldNotBeEncodedStillAnswersTheTap() async throws {
        let service = service(FakeTransport(answer: ["sender": "Maya", "message": "hi"]))

        let sequence = tapReply()
        writer.recordFrame(screen)
        let ticket = try XCTUnwrap(
            service.claim(
                intent: writer.intent(), identity: screen.identity, capturedAt: CaptureClock.now()))
        service.fail(ticket, detail: "The screen could not be prepared for reading.")

        let record = try await record(answering: sequence)
        XCTAssertEqual(record.outcome, .failed)
        XCTAssertEqual(record.detail, "The screen could not be prepared for reading.")
    }

    /// None of the three non-readings may be shown as one. `CaptureFreshness`
    /// refuses them even when every liveness and identity condition holds, which
    /// is the state a record written a moment ago about the frame on screen is in.
    func testTheFreshnessGateNeverOffersARecordThatCarriesNoReading() async throws {
        let service = service(FakeTransport(failure: .network("no route to host")))

        let sequence = tapReply()
        XCTAssertNotNil(sample(service, showing: screen))
        let failed = try await record(answering: sequence)

        // Confirm it the way a good reading gets confirmed: a frame of the same
        // screen, sampled after the read finished.
        writer.recordFrame(screen)
        XCTAssertEqual(
            CaptureFreshness.evaluate(record: failed, status: keyboard.status().status),
            .superseded)

        let reading = ScreenReadingRecord(
            sessionID: session, requestSequence: sequence, frameIdentity: screen.identity,
            capturedAt: failed.capturedAt, readAt: failed.readAt, provenance: "cloud",
            sender: "Maya", message: "Are we still on?",
            language: KeyboardLanguage.english.rawValue)
        XCTAssertEqual(
            CaptureFreshness.evaluate(record: reading, status: keyboard.status().status),
            .offerable,
            "the same record carrying a reading is offerable, so the refusal above is the outcome")
    }

    // MARK: The promise

    /// The product promise, checked against the filesystem rather than against a
    /// comment: text and hashes cross the App Group and pixels do not.
    func testNoPixelsReachTheContainer() async throws {
        let service = service(FakeTransport(answer: ["sender": "Maya", "message": "hi"]))

        let sequence = tapReply()
        XCTAssertNotNil(sample(service, showing: screen))
        _ = try await record(answering: sequence)

        let files = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)
        XCTAssertEqual(
            Set(files.map(\.lastPathComponent)), ["status.bin", "intent.bin", "reading.json"])

        for file in files {
            let bytes = try Data(contentsOf: file)
            XCTAssertNil(
                bytes.range(of: Data([0xFF, 0xD8, 0xFF])),
                "\(file.lastPathComponent) contains a JPEG header")
            XCTAssertNil(bytes.range(of: jpeg), "\(file.lastPathComponent) contains the frame")
        }

        let json = try JSONSerialization.jsonObject(
            with: Data(contentsOf: directory.appendingPathComponent("reading.json")))
        let keys = Set((json as? [String: Any] ?? [:]).keys)
        XCTAssertEqual(
            keys,
            [
                "sessionID", "requestSequence", "frameIdentity", "capturedAt", "readAt",
                "provenance", "outcome", "detail", "sender", "message", "language"
            ],
            "a new field on the record is a new thing crossing the boundary; check what it is")
    }

    // MARK: Counters

    /// The counters are how a device run says what happened, since nothing else
    /// about this process is observable from the phone.
    func testTheCountersReportWhatTheSessionDid() async throws {
        let transport = FakeTransport(answer: ["sender": "Maya", "message": "hi"])
        let service = service(transport)

        let sequence = tapReply()
        XCTAssertNotNil(sample(service, showing: screen))
        _ = try await record(answering: sequence)

        let status = try status()
        XCTAssertEqual(status.readsRequested, 1)
        XCTAssertEqual(status.readsStarted, 1)
        XCTAssertEqual(status.readsCompleted, 1)
        XCTAssertEqual(status.refusedInFlight, 0)
    }
}

// MARK: - A transport that answers what the test says

/// Stands in for the backend. It records what it was asked, answers with a
/// fixed set of fields or an error, and can be held open so a second request
/// arrives while the first is still running.
private final class FakeTransport: CloudTransport, @unchecked Sendable {

    private let lock = NSLock()
    private var _calls = 0
    private var _requests: [CloudRequest] = []
    private let gate = Gate()

    let answer: [String: String]
    let failure: AIEngineError?
    /// When true, `send` waits for `release()` before answering.
    var holdOpen = false

    init(answer: [String: String] = [:], failure: AIEngineError? = nil) {
        self.answer = answer
        self.failure = failure
    }

    var calls: Int {
        lock.lock()
        defer { lock.unlock() }
        return _calls
    }

    var requests: [CloudRequest] {
        lock.lock()
        defer { lock.unlock() }
        return _requests
    }

    func send(_ request: CloudRequest) async throws -> [String: String] {
        lock.lock()
        _calls += 1
        _requests.append(request)
        lock.unlock()
        await gate.arrived()

        if holdOpen { await gate.wait() }
        if let failure { throw failure }
        return answer
    }

    /// Returns once `send` has been entered, so a test can be sure the read is
    /// genuinely in flight before it taps again.
    func waitUntilCalled() async throws { await gate.waitForArrival() }

    func release() async { await gate.open() }
}

/// Two one-shot signals, both directions. An actor rather than a semaphore
/// because the thing being coordinated is an `async` call and blocking a test
/// thread on one is how a test deadlocks the cooperative pool.
private actor Gate {
    private var isOpen = false
    private var hasArrived = false
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private var watching: [CheckedContinuation<Void, Never>] = []

    func arrived() {
        hasArrived = true
        watching.forEach { $0.resume() }
        watching = []
    }

    func waitForArrival() async {
        guard !hasArrived else { return }
        await withCheckedContinuation { watching.append($0) }
    }

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiting.append($0) }
    }

    func open() {
        isOpen = true
        waiting.forEach { $0.resume() }
        waiting = []
    }
}
