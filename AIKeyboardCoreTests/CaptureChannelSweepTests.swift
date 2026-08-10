import XCTest
import os

@testable import AIKeyboardCore

/// Container-sweeping, session-lifetime, concurrent-access, and keyboard-side
/// read-discard tests extracted from `CaptureChannelTests`.
final class CaptureChannelSweepTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("capture-channel-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func url(_ name: String) -> URL { directory.appendingPathComponent(name) }

    /// `channel/` under the scratch container, created — the writer opens
    /// `status.bin` with `O_CREAT` but will not make the directory holding it.
    private func liveChannelDirectory() throws -> URL {
        let live = directory.appendingPathComponent("channel", isDirectory: true)
        try FileManager.default.createDirectory(at: live, withIntermediateDirectories: true)
        return live
    }

    private func record(session: UUID) -> ScreenReadingRecord {
        let now = CaptureClock.now()
        return ScreenReadingRecord(
            sessionID: session,
            requestSequence: 1,
            frameIdentity: FrameIdentity(w0: 1, w1: 2, w2: 3, w3: 4),
            capturedAt: now,
            readAt: now,
            provenance: "cloud",
            sender: "Maya",
            message: "Are we still on for 6?",
            language: KeyboardLanguage.english.rawValue)
    }

    // MARK: - The record

    func testTheReadingRecordSurvivesJSON() throws {
        let rec = ScreenReadingRecord(
            sessionID: UUID(),
            requestSequence: 3,
            frameIdentity: FrameIdentity(w0: 9, w1: 8, w2: 7, w3: 6),
            capturedAt: 1_000,
            readAt: 2_000,
            provenance: "cloud",
            sender: "Maya",
            message: "מתי אתה מגיע?",
            language: KeyboardLanguage.hebrew.rawValue)

        let data = try JSONEncoder().encode(rec)
        XCTAssertEqual(try JSONDecoder().decode(ScreenReadingRecord.self, from: data), rec)
        XCTAssertEqual(rec.keyboardLanguage, .hebrew)
    }

    // MARK: - Sweeping the container

    /// The container accumulates debris.
    func testSweepRemovesOrphanedChannelDirectoriesAndLeavesTheLiveOne() throws {
        let manager = FileManager.default
        let live = directory.appendingPathComponent("channel", isDirectory: true)
        for name in ["channel", "channel-com.nitai.aikeyboard", "channel-com.nitai.aikeyboard.keyboard"] {
            try manager.createDirectory(
                at: directory.appendingPathComponent(name, isDirectory: true),
                withIntermediateDirectories: true)
        }
        let writer = try XCTUnwrap(CaptureChannelWriter(directory: live))
        writer.begin()

        let removed = CaptureChannel.sweep(container: directory)

        XCTAssertEqual(
            Set(removed), ["channel-com.nitai.aikeyboard", "channel-com.nitai.aikeyboard.keyboard"])
        XCTAssertTrue(manager.fileExists(atPath: live.appendingPathComponent("status.bin").path))
        XCTAssertNotNil(writer.status(), "the live page is still the one both processes have mapped")
    }

    /// A file that merely starts with the same letters is not a channel directory.
    func testSweepLeavesFilesAndUnrelatedDirectoriesAlone() throws {
        let manager = FileManager.default
        try manager.createDirectory(
            at: directory.appendingPathComponent("Library", isDirectory: true),
            withIntermediateDirectories: true)
        try Data("x".utf8).write(to: directory.appendingPathComponent("channel-notes.txt"))

        XCTAssertEqual(CaptureChannel.sweep(container: directory), [])
        XCTAssertTrue(manager.fileExists(atPath: directory.appendingPathComponent("Library").path))
        XCTAssertTrue(
            manager.fileExists(atPath: directory.appendingPathComponent("channel-notes.txt").path))
    }

    func testSweepRemovesAReadingWhoseProducerIsGone() throws {
        let live = try liveChannelDirectory()
        let writer = try XCTUnwrap(CaptureChannelWriter(directory: live))
        let session = writer.begin(now: CaptureClock.now() - CaptureClock.nanoseconds(3_600))
        try writer.publish(record(session: session))

        let removed = CaptureChannel.sweep(container: directory)

        XCTAssertEqual(removed, ["channel/reading.json"])
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: live.appendingPathComponent("reading.json").path))
    }

    func testSweepKeepsAReadingWhileTheProducerIsStillBeating() throws {
        let live = try liveChannelDirectory()
        let writer = try XCTUnwrap(CaptureChannelWriter(directory: live))
        let session = writer.begin()
        writer.heartbeat()
        try writer.publish(record(session: session))

        XCTAssertEqual(CaptureChannel.sweep(container: directory), [])
        XCTAssertNotNil(
            CaptureChannelReader(directory: live).reading(),
            "a live session's reading is the one thing in here that is still true")
    }

    /// A recorded ending is an ending even while the heartbeat is inside its window.
    func testSweepRemovesAReadingAfterARecordedEnding() throws {
        let live = try liveChannelDirectory()
        let writer = try XCTUnwrap(CaptureChannelWriter(directory: live))
        let session = writer.begin()
        try writer.publish(record(session: session))
        writer.end(.stopped)
        try JSONEncoder().encode(record(session: session))
            .write(to: live.appendingPathComponent("reading.json"))

        XCTAssertEqual(CaptureChannel.sweep(container: directory), ["channel/reading.json"])
    }

    // MARK: - A message must not outlive its session

    func testAReadingPublishedAfterTheSessionEndedIsRefused() throws {
        let writer = try XCTUnwrap(CaptureChannelWriter(directory: directory))
        let session = writer.begin()
        let readingURL = url("reading.json")

        try writer.publish(record(session: session))
        XCTAssertTrue(FileManager.default.fileExists(atPath: readingURL.path))

        writer.end(.stopped)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: readingURL.path), "end() deletes what it owns")

        XCTAssertThrowsError(try writer.publish(record(session: session))) { error in
            XCTAssertEqual(error as? CaptureChannelError, .sessionEnded)
        }
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: readingURL.path),
            "a message that outlived its session is a privacy leak, not untidiness")
    }

    func testNoInterleavingOfEndAndPublishLeavesAReadingBehind() throws {
        let writer = try XCTUnwrap(CaptureChannelWriter(directory: directory))
        let readingURL = url("reading.json")

        for _ in 0..<200 {
            let session = writer.begin()
            let group = DispatchGroup()
            DispatchQueue.global(qos: .userInitiated).async(group: group) {
                try? writer.publish(self.record(session: session))
            }
            DispatchQueue.global(qos: .userInitiated).async(group: group) {
                writer.end(.stopped)
            }
            group.wait()

            XCTAssertFalse(
                FileManager.default.fileExists(atPath: readingURL.path),
                "a reading survived a session that ended while it was being published")
        }
    }

    func testANewSessionPublishesAgain() throws {
        let writer = try XCTUnwrap(CaptureChannelWriter(directory: directory))
        writer.end(.stopped)
        let session = writer.begin()

        XCTAssertNoThrow(try writer.publish(record(session: session)))
        XCTAssertNotNil(CaptureChannelReader(directory: directory).reading())
    }

    // MARK: - The intent mapping is opened from two queues

    func testIntentCanBeOpenedFromTwoQueuesAtOnce() throws {
        for _ in 0..<50 {
            let scratch = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
            let writer = try XCTUnwrap(CaptureChannelWriter(directory: scratch))
            let reader = CaptureChannelReader(directory: scratch)
            reader.requestRead()

            let group = DispatchGroup()
            let seen = OSAllocatedUnfairLock(initialState: [UInt64]())
            for _ in 0..<8 {
                DispatchQueue.global(qos: .userInitiated).async(group: group) {
                    let readNow = writer.intent()?.readNow ?? 0
                    seen.withLock { $0.append(readNow) }
                }
            }
            group.wait()

            XCTAssertTrue(
                seen.withLock { $0.allSatisfy { $0 == 1 } },
                "every caller sees the same page, or one of them read through a freed mapping")
        }
    }

    func testStatusCanBeOpenedFromTwoQueuesAtOnce() throws {
        for _ in 0..<50 {
            let scratch = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
            let writer = try XCTUnwrap(CaptureChannelWriter(directory: scratch))
            let session = writer.begin()
            let reader = CaptureChannelReader(directory: scratch)

            let group = DispatchGroup()
            let seen = OSAllocatedUnfairLock(initialState: [UUID?]())
            for _ in 0..<8 {
                DispatchQueue.global(qos: .userInitiated).async(group: group) {
                    let identity = reader.status().status?.sessionID
                    seen.withLock { $0.append(identity) }
                }
            }
            group.wait()

            XCTAssertTrue(
                seen.withLock { $0.allSatisfy { $0 == session } },
                "every caller sees the same page, or one of them read through a freed mapping")
        }
    }

    // MARK: The keyboard sweeps for itself

    func testTheKeyboardUnlinksAReadingWhoseProducerIsGone() throws {
        let live = try liveChannelDirectory()
        let writer = try XCTUnwrap(CaptureChannelWriter(directory: live))
        let session = writer.begin(now: CaptureClock.now() - CaptureClock.nanoseconds(3_600))
        try writer.publish(record(session: session))

        let reader = CaptureChannelReader(directory: live)
        XCTAssertNotNil(reader.reading(), "the text is on disk before the keyboard arrives")

        XCTAssertTrue(reader.discardReadingOfADeadSession())

        XCTAssertNil(reader.reading())
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: live.appendingPathComponent("reading.json").path),
            "the file itself has to go, not just the decode")
    }

    func testTheKeyboardLeavesALiveSessionsReadingAlone() throws {
        let live = try liveChannelDirectory()
        let writer = try XCTUnwrap(CaptureChannelWriter(directory: live))
        let session = writer.begin()
        writer.heartbeat()
        try writer.publish(record(session: session))

        let reader = CaptureChannelReader(directory: live)
        XCTAssertFalse(reader.discardReadingOfADeadSession())
        XCTAssertNotNil(reader.reading())
    }
}
