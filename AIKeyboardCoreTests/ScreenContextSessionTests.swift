import CoreGraphics
import Foundation
import XCTest

@testable import AIKeyboardCore

// MARK: - Doubles

/// A reader that answers from a script, so the session's state machine can be
/// driven without pixels, a model or a network. `ScreenContextBarTests` drives
/// the same session with the real readers and the real frames.
private final class ScriptedReader: ScreenReader, @unchecked Sendable {

    enum Answer {
        case reading(ScreenReading)
        /// The reader looked and there was nothing worth replying to. A real
        /// answer, not a failure — a voice note, or a screen whose last message
        /// is the user's own.
        case nothingToReplyTo
        case failure(any Error)
    }

    private let lock = NSLock()
    private var script: [Answer]
    private var lastAnswer: Answer
    private var calls = 0

    init(_ script: [Answer]) {
        self.script = script
        self.lastAnswer = script.last ?? .nothingToReplyTo
    }

    /// How many frames actually reached the reader. Proves the session did not
    /// silently swallow one.
    var callCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return calls
    }

    func read(_ frame: CGImage) async throws -> AIOutput<ScreenReading?> {
        let answer: Answer = {
            lock.lock()
            defer { lock.unlock() }
            calls += 1
            return script.isEmpty ? lastAnswer : script.removeFirst()
        }()

        switch answer {
        case .reading(let reading): return AIOutput(reading, provenance: .onDevice)
        case .nothingToReplyTo: return AIOutput(nil, provenance: .onDevice)
        case .failure(let error): throw error
        }
    }
}

private func reading(_ sender: String, _ message: String) -> ScreenReading {
    ScreenReading(sender: sender, message: message, language: .english, scripts: [.latin])
}

/// Four pixels. The session hands the frame straight to the reader, so nothing
/// here depends on what it contains.
private func blankFrame() -> CGImage {
    let context = CGContext(
        data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    return context.makeImage()!
}

// MARK: - Session

/// The state machine behind the strip the user actually looks at.
///
/// Every case here is a thing that shows on screen: a reply offered for a
/// message that is no longer the newest one, a session stuck on "starting", a
/// strip that goes quiet after one unreadable frame.
@MainActor
final class ScreenContextSessionStateTests: XCTestCase {

    private let session = ScreenContextSession.shared
    private let frame = blankFrame()

    override func setUp() async throws {
        session.stop()
        session.reader = nil
    }

    override func tearDown() async throws {
        session.stop()
        session.reader = nil
    }

    /// A capture backend is attached, so the session waits for real frames
    /// rather than running the mock timeline `start()` uses on its own. Without
    /// this the sample context lands on top of a real reading two seconds in.
    func testASessionWithAReaderAttachedWaitsForRealFrames() async throws {
        session.reader = ScriptedReader([])
        session.start()

        XCTAssertEqual(session.state, .watching)
        try await Task.sleep(for: .milliseconds(2600))
        XCTAssertEqual(
            session.state, .watching,
            "the scripted mock timeline must not overwrite a real reader's session")
        XCTAssertEqual(session.framesRead, 0, "no frame was submitted, so none was read")
    }

    func testAReadingMovesTheSessionToReady() async {
        session.reader = ScriptedReader([.reading(reading("Nadia", "Are we still on for Thursday?"))])
        session.start()

        await session.submit(frame, appName: "Messages", appIcon: "bubble.left.fill")

        let context = session.state.context
        XCTAssertEqual(context?.sender, "Nadia")
        XCTAssertEqual(context?.message, "Are we still on for Thursday?")
        XCTAssertEqual(context?.language, .english)
        XCTAssertEqual(context?.appName, "Messages")
        XCTAssertEqual(context?.appIcon, "bubble.left.fill")
        XCTAssertEqual(session.framesRead, 1)
    }

    /// The one that matters most. The user scrolls past the message that was
    /// read, or answers it; the next frame has nothing repliable on it. Leaving
    /// the old reply on screen offers an answer to a conversation that has
    /// moved on.
    func testNothingRepliableClearsAStaleReady() async {
        session.reader = ScriptedReader([
            .reading(reading("Nadia", "Are we still on for Thursday?")),
            .nothingToReplyTo
        ])
        session.start()

        await session.submit(frame, appName: "Messages", appIcon: "bubble.left.fill")
        XCTAssertNotNil(session.state.context)

        await session.submit(frame, appName: "Messages", appIcon: "bubble.left.fill")

        XCTAssertEqual(session.state, .watching)
        XCTAssertNil(session.state.context, "a stale reply must not survive a frame that said nothing")
        XCTAssertEqual(session.framesRead, 2, "a frame that said nothing was still read")
    }

    func testNothingRepliableOnAQuietSessionStaysWatching() async {
        session.reader = ScriptedReader([.nothingToReplyTo])
        session.start()

        await session.submit(frame, appName: "WhatsApp", appIcon: "message.fill")

        XCTAssertEqual(session.state, .watching)
    }

    /// One frame that could not be read is not worth a message to the user —
    /// another arrives in a moment. What matters is that the session is still
    /// taking frames afterwards.
    func testAThrowingReaderDoesNotWedgeTheSession() async {
        let reader = ScriptedReader([
            .failure(ScreenReadError.failed("the frame could not be encoded")),
            .failure(ScreenReadError.network("offline")),
            .reading(reading("Yusuf", "Did the invoice for June ever get paid?"))
        ])
        session.reader = reader
        session.start()

        await session.submit(frame, appName: "Telegram", appIcon: "paperplane.fill")
        XCTAssertEqual(session.state, .watching)
        await session.submit(frame, appName: "Telegram", appIcon: "paperplane.fill")
        XCTAssertEqual(session.state, .watching)

        await session.submit(frame, appName: "Telegram", appIcon: "paperplane.fill")

        XCTAssertEqual(session.state.context?.sender, "Yusuf")
        XCTAssertEqual(reader.callCount, 3, "every frame reached the reader")
        XCTAssertEqual(session.framesRead, 3)
    }

    /// A reader with no cloud half throws `.noCloudReader` on every Hebrew
    /// screen. The strip stays quiet; it does not sit on "starting" forever.
    func testAReaderThatNeverSucceedsLeavesTheSessionWatching() async {
        session.reader = ScriptedReader([.failure(ScreenReadError.noCloudReader)])
        session.start()

        for _ in 0..<5 {
            await session.submit(frame, appName: "WhatsApp", appIcon: "message.fill")
        }

        XCTAssertEqual(session.state, .watching)
        XCTAssertEqual(session.framesRead, 5)
    }

    func testFramesAreIgnoredWhileTheSessionIsOff() async {
        let reader = ScriptedReader([.reading(reading("Nadia", "hello"))])
        session.reader = reader

        await session.submit(frame, appName: "Messages", appIcon: "bubble.left.fill")

        XCTAssertEqual(session.state, .off)
        XCTAssertEqual(reader.callCount, 0, "a stopped session must not read the screen")
        XCTAssertEqual(session.framesRead, 0)
    }

    func testStoppingClearsTheContext() async {
        session.reader = ScriptedReader([.reading(reading("Nadia", "hello"))])
        session.start()
        await session.submit(frame, appName: "Messages", appIcon: "bubble.left.fill")
        XCTAssertNotNil(session.state.context)

        session.stop()

        XCTAssertEqual(session.state, .off)
        XCTAssertNil(session.state.context)
        XCTAssertEqual(session.framesRead, 0)
    }
}

// MARK: - Routing

private struct FixedReader: ScreenReader {
    let answer: ScreenReading?
    let provenance: AIProvenance
    let failure: (any Error)?
    let calls: Counter

    final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        var count: Int {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
        func increment() {
            lock.lock()
            value += 1
            lock.unlock()
        }
    }

    init(
        answer: ScreenReading? = nil,
        provenance: AIProvenance = .onDevice,
        failure: (any Error)? = nil
    ) {
        self.answer = answer
        self.provenance = provenance
        self.failure = failure
        self.calls = Counter()
    }

    func read(_ frame: CGImage) async throws -> AIOutput<ScreenReading?> {
        calls.increment()
        if let failure { throw failure }
        return AIOutput(answer, provenance: provenance)
    }
}

final class RoutedScreenReaderTests: XCTestCase {

    private let frame = blankFrame()

    /// The Hebrew case, which is every Hebrew screen in the product: the
    /// on-device recogniser reports it could not read enough of the screen, and
    /// the frame goes to the cloud.
    func testAnUnreadableScreenGoesToTheCloud() async throws {
        let onDevice = FixedReader(failure: ScreenReadError.notReadableOnDevice)
        let cloud = FixedReader(answer: reading("שרה", "מתי נפגשים?"), provenance: .cloud)

        let output = try await RoutedScreenReader(onDevice: onDevice, cloud: cloud).read(frame)

        XCTAssertEqual(output.value?.sender, "שרה")
        XCTAssertEqual(output.provenance, .cloud)
        XCTAssertEqual(cloud.calls.count, 1)
    }

    func testAReadableScreenNeverLeavesTheDevice() async throws {
        let onDevice = FixedReader(answer: reading("Nadia", "Are we still on for Thursday?"))
        let cloud = FixedReader(answer: reading("wrong", "wrong"), provenance: .cloud)

        let output = try await RoutedScreenReader(onDevice: onDevice, cloud: cloud).read(frame)

        XCTAssertEqual(output.value?.sender, "Nadia")
        XCTAssertEqual(output.provenance, .onDevice)
        XCTAssertEqual(cloud.calls.count, 0, "a screen the device could read must not be uploaded")
    }

    /// **A known defect, pinned so a fix has to come here and change it.**
    ///
    /// `VisionScreenReader` has two different ways of declining. It *throws*
    /// `.notReadableOnDevice` when its readability gate fails, and the router
    /// turns that into a cloud call. It *returns nil* when the gate passed but
    /// the layout gave it nothing to work with — a one-sided Slack thread,
    /// where its own doc comment says "the router turns it into a cloud call
    /// rather than a wrong name". It does not: nil is an answer, so the router
    /// hands "nothing to reply to" straight to the session.
    ///
    /// Measured cost on `Bar/screen-context/`: `sl-01` and `sl-03` carry a
    /// perfectly answerable English message that the cloud reads correctly, and
    /// the shipping path offers the user nothing on either. See
    /// `ScreenContextBarTests`.
    func testARefusalWithoutAnErrorNeverReachesTheCloud() async throws {
        let onDevice = FixedReader(answer: nil)
        let cloud = FixedReader(
            answer: reading("Daniel Cohen", "Anyone still merging into main?"), provenance: .cloud)

        let output = try await RoutedScreenReader(onDevice: onDevice, cloud: cloud).read(frame)

        XCTAssertNil(output.value)
        XCTAssertEqual(cloud.calls.count, 0)
    }

    func testAFailureThatIsNotAboutReadabilityIsNotRetriedInTheCloud() async {
        let onDevice = FixedReader(failure: ScreenReadError.failed("the frame could not be encoded"))
        let cloud = FixedReader(answer: reading("Nadia", "hello"), provenance: .cloud)

        do {
            _ = try await RoutedScreenReader(onDevice: onDevice, cloud: cloud).read(frame)
            XCTFail("expected the failure to surface")
        } catch let error as ScreenReadError {
            XCTAssertEqual(error, .failed("the frame could not be encoded"))
            XCTAssertEqual(cloud.calls.count, 0)
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    /// The state this build actually ships in: no backend is configured, so
    /// every Hebrew screen ends here. Saying so is better than a wrong reading.
    func testNoCloudReaderIsReportedRatherThanGuessed() async {
        let onDevice = FixedReader(failure: ScreenReadError.notReadableOnDevice)

        do {
            _ = try await RoutedScreenReader(onDevice: onDevice, cloud: nil).read(frame)
            XCTFail("expected .noCloudReader")
        } catch let error as ScreenReadError {
            XCTAssertEqual(error, .noCloudReader)
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }
}
