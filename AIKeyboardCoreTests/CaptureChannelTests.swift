import XCTest

@testable import AIKeyboardCore

/// The transport under the capture channel: the shared page, its seqlock, and
/// the fixed layouts both processes agree on.
///
/// **What this file can and cannot prove.** Two `SharedPage` objects over one
/// file inside one process is the same `mmap` of the same inode that two
/// processes get, so the seqlock and the layout are genuinely exercised here.
/// What it does not and cannot show is that the *App Group* delivers that file
/// to a second process: a process always sees its own writes, and
/// `UserDefaults(suiteName:)` and `containerURL(...)` both succeed inside a test
/// bundle in ways that prove nothing about a keyboard extension's sandbox. That
/// verdict comes from `Scripts/prove-capture-channel.sh`, which reads it out of a
/// log line stamped by the other process.
final class CaptureChannelTests: XCTestCase {

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

    // MARK: - Layout

    /// The two page sizes are a file format, not an implementation detail: the
    /// broadcast extension and the keyboard map the same bytes and a struct that
    /// outgrew its page would be read as garbage by whichever side shipped
    /// first. Both fit with room for the fields §7 still wants.
    func testTheFixedLayoutsFitTheirPages() {
        let header = 8
        XCTAssertLessThanOrEqual(
            MemoryLayout<CaptureStatus>.size + header, CaptureChannel.statusPageBytes,
            "CaptureStatus is \(MemoryLayout<CaptureStatus>.size) bytes and the page is 256")
        XCTAssertLessThanOrEqual(
            MemoryLayout<CaptureIntent>.size + header, CaptureChannel.intentPageBytes)
        XCTAssertEqual(MemoryLayout<FrameIdentity>.size, 32, "a SHA-256 is 32 bytes")
    }

    func testSessionIdentifierSurvivesTheWordSplit() {
        let id = UUID()
        var status = CaptureStatus()
        status.setSessionID(id)
        XCTAssertEqual(status.sessionID, id)
        XCTAssertNil(CaptureStatus().sessionID, "an unwritten page claims no session")
    }

    // MARK: - The page

    func testAPageRoundTripsThroughTheFilesystem() throws {
        let file = url("status.bin")
        let writer = try XCTUnwrap(
            SharedPage<CaptureStatus>(
                url: file, bytes: CaptureChannel.statusPageBytes, writable: true))

        var status = CaptureStatus()
        status.setSessionID(UUID())
        status.framesSampled = 41
        status.currentFrameIdentity = FrameIdentity(w0: 1, w1: 2, w2: 3, w3: 4)
        writer.store(status)

        let reader = try XCTUnwrap(
            SharedPage<CaptureStatus>(
                url: file, bytes: CaptureChannel.statusPageBytes, writable: false))
        XCTAssertEqual(reader.load(), status)
    }

    /// The reader's mapping is of the same inode, so a write made after it
    /// opened is visible to it with no reopen, no notification and no
    /// synchronise call. This is the property the whole transport rests on.
    func testASecondMappingSeesWritesMadeAfterItOpened() throws {
        let file = url("status.bin")
        let writer = try XCTUnwrap(
            SharedPage<CaptureStatus>(
                url: file, bytes: CaptureChannel.statusPageBytes, writable: true))
        writer.store(CaptureStatus())

        let reader = try XCTUnwrap(
            SharedPage<CaptureStatus>(
                url: file, bytes: CaptureChannel.statusPageBytes, writable: false))
        XCTAssertEqual(reader.load()?.framesSampled, 0)

        writer.mutate { $0.framesSampled = 7 }
        XCTAssertEqual(reader.load()?.framesSampled, 7)

        writer.reset()
        XCTAssertEqual(reader.load()?.framesSampled, 0, "reset clears the page, not just a field")
    }

    func testAReadOnlyPageRefusesAFileThatIsNotThere() {
        XCTAssertNil(
            SharedPage<CaptureStatus>(
                url: url("never-written.bin"), bytes: CaptureChannel.statusPageBytes,
                writable: false),
            "no producer has ever run, and that is a state to report rather than to invent")
    }

    /// The seqlock's actual job, and the only test in this file that would fail
    /// if it were deleted.
    ///
    /// The writer keeps two fields in step — the frame counter and the sampled
    /// timestamp — and changes both on every write. Without the sequence number a
    /// reader eventually catches a write halfway and sees one frame's count
    /// beside another frame's timestamp, which in the shipping struct is one
    /// frame's *identity* beside another frame's timestamp: a reading confirmed
    /// against a frame that never existed.
    func testAConcurrentReaderNeverSeesHalfOfAWrite() throws {
        let file = url("status.bin")
        let writer = try XCTUnwrap(
            SharedPage<CaptureStatus>(
                url: file, bytes: CaptureChannel.statusPageBytes, writable: true))
        writer.store(CaptureStatus())
        let reader = try XCTUnwrap(
            SharedPage<CaptureStatus>(
                url: file, bytes: CaptureChannel.statusPageBytes, writable: false))

        let writes = 20_000
        let finished = expectation(description: "writer finished")
        DispatchQueue.global(qos: .userInitiated).async {
            for step in 1...writes {
                var status = CaptureStatus()
                status.framesSampled = UInt32(step)
                status.currentFrameSampledAt = UInt64(step)
                status.currentFrameIdentity = FrameIdentity(
                    w0: UInt64(step), w1: UInt64(step), w2: UInt64(step), w3: UInt64(step))
                writer.store(status)
            }
            finished.fulfill()
        }

        var reads = 0
        var torn = 0
        while reads < 200_000 {
            guard let status = reader.load() else { continue }
            reads += 1
            if UInt64(status.framesSampled) != status.currentFrameSampledAt
                || status.currentFrameIdentity.w0 != UInt64(status.framesSampled)
            {
                torn += 1
            }
            if status.framesSampled == UInt32(writes) { break }
        }

        wait(for: [finished], timeout: 30)
        XCTAssertEqual(torn, 0, "the reader saw \(torn) torn snapshots in \(reads) reads")
        XCTAssertGreaterThan(reads, 0)
    }

    /// The same page, written from **two** threads, which is what the shipping
    /// producer actually does.
    ///
    /// `SampleHandler` writes `status.bin` from three threads inside one process:
    /// ReplayKit's delivery queue through `recordFrame`, the 1 Hz heartbeat timer
    /// on `.global(qos: .utility)`, and whatever queue ReplayKit calls the
    /// lifecycle methods on through `setPaused` and `end`. A seqlock does not make
    /// that safe on its own and the three ways it breaks are all measurable:
    ///
    /// 1. **Torn settled bytes.** Two overlapping `begin_write`s can leave the
    ///    sequence *even* while the body is half-written, so `read_valid` returns
    ///    true over bytes that are not a snapshot of anything — and every bit
    ///    pattern this struct can hold is a legal value, so nothing crashes.
    /// 2. **Lost update**, which is the product failure the design exists to
    ///    prevent. The heartbeat's read-modify-write writes back a body it
    ///    snapshotted before a frame write, so `currentFrameIdentity` moves
    ///    *backwards* and a reading already retired as `.superseded` becomes
    ///    `.offerable` again: a reply in the user's own voice about the
    ///    conversation they just left.
    /// 3. **A permanent wedge.** Interleaved `end_write`s flip the sequence's
    ///    parity; from then on every settled state is odd, `load()` never passes
    ///    its `opened & 1 == 0` guard, and `status()` returns nil for the rest of
    ///    the session.
    ///
    /// So the four assertions are one per failure mode plus the reader's own
    /// liveness: zero torn snapshots, an identity that never goes backwards, an
    /// even raw sequence once the writers stop, and a page that still loads.
    ///
    /// Measured against the unfixed `SharedPage` on this destination, and the two
    /// runs hit different subsets of the three, which is what a race looks like:
    /// run 1 wedged the sequence odd after 5,766 reads with 168 tears and 1,000 of
    /// 1,000 quiescent loads nil; run 2 stayed even and scored 150 tears in 399,094
    /// reads plus one backwards step. With the writer lock the four counts are 0,
    /// 0, even, 0 — not statistically small, but excluded.
    func testTwoWriterThreadsCannotTearOrWedgeThePage() throws {
        let file = url("status.bin")
        let writer = try XCTUnwrap(
            SharedPage<CaptureStatus>(
                url: file, bytes: CaptureChannel.statusPageBytes, writable: true))
        writer.store(CaptureStatus())
        let reader = try XCTUnwrap(
            SharedPage<CaptureStatus>(
                url: file, bytes: CaptureChannel.statusPageBytes, writable: false))

        let writes = 20_000
        let frames = expectation(description: "frame writer finished")
        let heartbeats = expectation(description: "heartbeat writer finished")

        // The delivery queue's write: the counter, the sampled timestamp and the
        // identity all move together, exactly as `recordFrame` moves them.
        DispatchQueue.global(qos: .userInitiated).async {
            for step in 1...writes {
                writer.mutate {
                    $0.framesDelivered &+= 1
                    $0.framesSampled = UInt32(step)
                    $0.lastFrameAt = UInt64(step)
                    $0.currentFrameSampledAt = UInt64(step)
                    $0.currentFrameIdentity = FrameIdentity(
                        w0: UInt64(step), w1: UInt64(step), w2: UInt64(step), w3: UInt64(step))
                }
            }
            frames.fulfill()
        }

        // The heartbeat's write: one field, and it is a read-modify-write of the
        // whole 256-byte body, which is what makes it able to lose a frame.
        DispatchQueue.global(qos: .utility).async {
            for step in 1...writes {
                writer.mutate { $0.heartbeatAt = UInt64(step) }
            }
            heartbeats.fulfill()
        }

        var reads = 0
        var torn = 0
        var backwards = 0
        var highest: UInt32 = 0
        // Bounded rather than "until the last write lands": a wedged sequence
        // makes every load nil forever, and a test that hangs reports nothing.
        for _ in 0..<400_000 {
            guard let status = reader.load() else { continue }
            reads += 1
            if UInt64(status.framesSampled) != status.currentFrameSampledAt
                || status.currentFrameIdentity.w0 != UInt64(status.framesSampled)
                || status.currentFrameIdentity.w3 != UInt64(status.framesSampled)
            {
                torn += 1
            }
            if status.framesSampled < highest { backwards += 1 }
            highest = max(highest, status.framesSampled)
        }

        wait(for: [frames, heartbeats], timeout: 60)

        // Quiescent: nobody is writing, so every load must settle. This is the
        // one that catches the permanent wedge, which is invisible to the tear
        // count because a wedged page hands out no snapshots at all.
        var nilLoads = 0
        for _ in 0..<1_000 where reader.load() == nil { nilLoads += 1 }

        XCTAssertEqual(torn, 0, "the reader saw \(torn) torn snapshots in \(reads) reads")
        XCTAssertEqual(
            backwards, 0,
            "the frame identity went backwards \(backwards) times: a retired reading became offerable")
        XCTAssertEqual(
            try Self.rawSequence(of: file) % 2, 0,
            "the sequence settled odd, so every future load() returns nil")
        XCTAssertEqual(
            nilLoads, 0, "\(nilLoads) of 1000 loads found no settled page after the writers stopped")
        XCTAssertGreaterThan(reads, 0)
    }

    /// The seqlock's own counter, read the way the other process's kernel sees it
    /// rather than through `SharedPage`: the mapping is `MAP_SHARED` over this
    /// inode, so the first four bytes of the file *are* the sequence.
    private static func rawSequence(of file: URL) throws -> UInt32 {
        let head = try Data(contentsOf: file).prefix(4)
        return head.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
    }

    // MARK: - The intent page

    func testRaisingAReadRequestIsMonotonic() throws {
        let file = url("intent.bin")
        let page = try XCTUnwrap(
            SharedPage<CaptureIntent>(
                url: file, bytes: CaptureChannel.intentPageBytes, writable: true))
        page.store(CaptureIntent())

        for expected in 1...5 {
            page.mutate { $0.readNow &+= 1 }
            XCTAssertEqual(page.load()?.readNow, UInt64(expected))
        }
    }

    /// The visibility flag carries a timestamp for the same reason the frame
    /// identity does. A keyboard extension is killed rather than dismissed often
    /// enough that a `1` outlives the process that wrote it, and a producer
    /// reading the bare flag would believe a keyboard that is not there.
    func testKeyboardVisibilityIsStampedWithWhenItWasWritten() throws {
        let file = url("intent.bin")
        let page = try XCTUnwrap(
            SharedPage<CaptureIntent>(
                url: file, bytes: CaptureChannel.intentPageBytes, writable: true))

        var stale = CaptureIntent()
        stale.keyboardVisible = 1
        stale.keyboardVisibleAt = CaptureClock.nanoseconds(100)
        page.store(stale)

        let sessionStart = CaptureClock.nanoseconds(500)
        let intent = try XCTUnwrap(page.load())
        XCTAssertTrue(intent.isKeyboardVisible)
        XCTAssertLessThan(
            intent.keyboardVisibleAt, sessionStart,
            "the flag is set but it was written before this session, so it means nothing")
    }

    // MARK: - The record

    func testTheReadingRecordSurvivesJSON() throws {
        let record = ScreenReadingRecord(
            sessionID: UUID(),
            requestSequence: 3,
            frameIdentity: FrameIdentity(w0: 9, w1: 8, w2: 7, w3: 6),
            capturedAt: 1_000,
            readAt: 2_000,
            provenance: "cloud",
            sender: "Maya",
            message: "מתי אתה מגיע?",
            language: KeyboardLanguage.hebrew.rawValue)

        let data = try JSONEncoder().encode(record)
        XCTAssertEqual(try JSONDecoder().decode(ScreenReadingRecord.self, from: data), record)
        XCTAssertEqual(record.keyboardLanguage, .hebrew)
    }

    // MARK: - Sweeping the container

    /// The container accumulates debris. Alongside the live `channel/` there were
    /// `channel-com.nitai.aikeyboard/` and `channel-com.nitai.aikeyboard.keyboard/`,
    /// left by an experiment that rooted the channel per process; shipping code
    /// has only ever opened `channel/`.
    ///
    /// Unlinking those is safe for the same reason unlinking `channel/status.bin`
    /// would not be: nothing has mapped them, so no reader is left holding an
    /// inode nobody will write to again. That asymmetry is why `clear()` still
    /// zeroes the live pages in place instead.
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

    /// A file that merely starts with the same letters is not a channel
    /// directory, and the sweep does not get to guess.
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

    /// `reading.json` carries a sender and the text of somebody's message, in a
    /// container that is backed up with the app. The producer deletes it in
    /// `begin()` and `end()`, and a jetsam kill fires neither — so without this it
    /// outlives the session it was read in by however long the phone runs.
    ///
    /// `CaptureFreshness` is what stops it being *shown*; this is a separate
    /// obligation from that one.
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

    /// A recorded ending is an ending even while the heartbeat is inside its
    /// window: the producer said it stopped.
    func testSweepRemovesAReadingAfterARecordedEnding() throws {
        let live = try liveChannelDirectory()
        let writer = try XCTUnwrap(CaptureChannelWriter(directory: live))
        let session = writer.begin()
        try writer.publish(record(session: session))
        // `end` deletes it too; write it back to test the sweep rather than that.
        writer.end(.deviceLocked)
        try writer.publish(record(session: session))

        XCTAssertEqual(CaptureChannel.sweep(container: directory), ["channel/reading.json"])
    }

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

    // MARK: - Settings nobody reads any more

    /// The same class of debris one layer up. A deleted property is not a deleted
    /// setting: `screenContextCloudReplies` backed a toggle that promised screen
    /// reading could stay on the device, no code ever read it, and the value it
    /// wrote is still in the App Group plist of every install that ran that build.
    func testRetiredSettingsKeysAreRemoved() throws {
        let suite = "retired-keys-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "screenContextCloudReplies")
        defaults.set(true, forKey: "screenContextAllowed")

        SharedStore.removeRetiredKeys(from: defaults)

        XCTAssertNil(defaults.object(forKey: "screenContextCloudReplies"))
        XCTAssertNotNil(
            defaults.object(forKey: "screenContextAllowed"),
            "a key the store still reads is not debris")
    }

    /// Every retired key has to be one no code reads. A key in both lists is a
    /// setting that would be wiped on the next launch.
    func testNoRetiredKeyIsStillInUse() {
        let live = Set(
            [
                "hasCompletedOnboarding", "enabledLanguages", "autocorrect", "autocapitalise",
                "predictions", "haptics", "keySounds", "onDeviceAI", "defaultTone",
                "personalDictionary", "isSubscribed", "screenContextAllowed", "cloudBackendURL"
            ])
        XCTAssertTrue(Set(SharedStore.retiredKeys).isDisjoint(with: live))
    }

    // MARK: - End reasons

    /// The five ReplayKit codes, from `RPError.h`. A code nobody recognised is
    /// still an ending, and reporting no reason for an ending that happened is
    /// worse than reporting a vague one.
    func testRecordingErrorCodesMapToEndReasons() {
        XCTAssertEqual(ScreenContextEndReason(recordingErrorCode: -5806), .interrupted)
        XCTAssertEqual(ScreenContextEndReason(recordingErrorCode: -5807), .contentResized)
        XCTAssertEqual(ScreenContextEndReason(recordingErrorCode: -5809), .deviceLocked)
        XCTAssertEqual(ScreenContextEndReason(recordingErrorCode: -5811), .phoneCall)
        XCTAssertEqual(ScreenContextEndReason(recordingErrorCode: -5813), .carPlay)
        XCTAssertEqual(ScreenContextEndReason(recordingErrorCode: -1), .interrupted)
        XCTAssertEqual(
            ScreenContextEndReason.none.rawValue, 0,
            "a zeroed page must not claim an ending")
    }
}
