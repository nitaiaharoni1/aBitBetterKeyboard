import Foundation
import XCTest

@testable import AIKeyboardCore
@testable import AIKeyboardShared

/// Answer, promise, and counter tests extracted from `ScreenReadServiceTests`.
final class ScreenReadServiceAnswerTests: XCTestCase {
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

    /// **The three sentences the text engine lends this path, and what they say
    /// instead.**
    ///
    /// `CloudIntelligence` and `CloudScreenReader` share `BackendTransport`, so a
    /// screen read fails through `BackendTransport.mapped` and lands on
    /// `AIEngineError` cases whose messages were written for a passage of text.
    /// The table below is the whole bug: each left-hand string is what the phone's
    /// owner was shown under "Couldn't read the screen", and every one of them is
    /// either false or an instruction about something that does not exist here.
    ///
    /// | Status | Borrowed sentence | Why it is wrong |
    /// |---|---|---|
    /// | 401/403 | "This language needs a cloud model, and none is set up in this build." | no language in a screen read, and one *is* set up |
    /// | 413 | "Select a shorter passage and try again." | nothing was selected; the input is a JPEG |
    /// | 422 | "Editing it slightly usually gets past it." | there is nothing to edit |
    ///
    /// Asserted against the borrowed strings by name, so this fails the moment
    /// `explain` falls back to `AIEngineError.message` for any of them again.
    func testAFailureAboutTheServerDoesNotBorrowTheTextEngineSCopy() {
        let cases: [(AIEngineError, String)] = [
            (.cloudNotConfigured, ScreenReadService.tokenRejected),
            (.failed(""), ScreenReadService.addressNotAServer),
            (.inputTooLong, "The screen was too large for the screen reading server to accept."),
            (.refused, "The screen reading server declined to read this screen.")
        ]
        for (error, expected) in cases {
            let shown = ScreenReadService.explain(error)
            XCTAssertEqual(shown, expected)
            XCTAssertNotEqual(
                shown, error.message,
                "\(error) is still printing the sentence written for the text engine")
        }

        for banned in ["language", "passage", "Editing it"] {
            for (error, _) in cases {
                XCTAssertFalse(
                    ScreenReadService.explain(error).localizedCaseInsensitiveContains(banned),
                    "a screen read told the user about \(banned)")
            }
        }

        // Everything else still comes from the enum, where the wording is right
        // for both paths.
        XCTAssertEqual(
            ScreenReadService.explain(AIEngineError.network("The backend is unreachable.")),
            "The backend is unreachable.")
    }

    /// **Which failures repeat**, so the strip can stop offering a read that
    /// cannot succeed.
    ///
    /// A rejected token and a wrong address fail identically on the next tap, and
    /// each of those taps costs another upload of the user's screen. A network
    /// blip does not, and must stay offerable.
    func testOnlySetupFailuresAreMarkedAsRepeating() {
        XCTAssertTrue(ScreenReadService.describesSetup(ScreenReadService.tokenRejected))
        XCTAssertTrue(ScreenReadService.describesSetup(ScreenReadService.addressNotAServer))
        XCTAssertTrue(ScreenReadService.describesSetup(ScreenReadService.notConfigured))

        XCTAssertFalse(ScreenReadService.describesSetup("The backend is unreachable."))
        XCTAssertFalse(
            ScreenReadService.describesSetup("The screen could not be prepared for reading."))
        XCTAssertFalse(ScreenReadService.describesSetup(""))
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
