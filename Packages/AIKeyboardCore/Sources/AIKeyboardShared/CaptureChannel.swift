import CaptureAtomics
import Foundation
import os

// MARK: - Where the channel lives

/// The App Group paths the capture channel uses, and the question that has a
/// false answer.
///
/// `UserDefaults(suiteName:)` hands back a usable object whether or not this
/// process is entitled to the group, so it proves nothing;
/// `containerURL(forSecurityApplicationGroupIdentifier:)` is nil without the
/// entitlement, and nil in the keyboard until the user grants Full Access. That
/// is the same probe `SharedStore` makes and for the same reason.
public enum CaptureChannel {

    public static let appGroupIdentifier = SharedContainer.appGroupIdentifier

    /// Fixed page sizes. Both are one struct plus an eight-byte sequence header,
    /// padded to a round number so a later field is a source change and not a
    /// file-format change.
    public static let statusPageBytes = 256
    public static let intentPageBytes = 64

    public static var directoryURL: URL? {
        SharedContainer.url?.appendingPathComponent("channel", isDirectory: true)
    }

    public static var statusURL: URL? { directoryURL?.appendingPathComponent("status.bin") }
    public static var intentURL: URL? { directoryURL?.appendingPathComponent("intent.bin") }
    public static var readingURL: URL? { directoryURL?.appendingPathComponent("reading.json") }

    /// True when this process can reach the shared container at all. False in
    /// the keyboard without Full Access, which is why screen context is a
    /// Full-Access-only feature end to end.
    public static var isReachable: Bool { SharedContainer.url != nil }

    static func prepareDirectory() -> URL? {
        guard let directory = directoryURL else { return nil }
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        return directory
    }
}

/// The App Group container, probed once.
public enum SharedContainer {
    public static let appGroupIdentifier = "group.com.nitai.aikeyboard"

    public static var url: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
    }
}

// MARK: - The shared page

/// One fixed-layout struct in a file two processes have mapped.
///
/// **Why this and not `UserDefaults`.** `SharedStore` uses `UserDefaults(suiteName:)`,
/// which is right for settings and wrong for a heartbeat: cross-process change
/// notification through `CFPreferences` has not been reliable since iOS 8 and it
/// synchronises opportunistically, so a 1 Hz liveness signal read through it
/// would be neither prompt nor trustworthy. `open(O_RDWR)` once and
/// `mmap(MAP_SHARED)` gives a memcpy write and a load read with no allocation,
/// no atomic rename and no notification machinery — which matters because the
/// write happens inside ReplayKit's 60 fps delivery callback in a process capped
/// at ~50 MB.
///
/// **Why a seqlock.** A 256-byte struct is not written atomically by anything, so
/// a reader can catch a write halfway and see one frame's identity beside the
/// next frame's timestamp — a reading confirmed against a frame that does not
/// exist. The sequence number at the head of the page turns that from a silent
/// wrong answer into a retry. `CaptureAtomics.h` says why the fences are in C.
///
/// **Why a lock as well as the seqlock, and why only on this side.** A seqlock
/// admits exactly one writer. One *process* writes each page, but the writing
/// process writes from several threads — `status.bin` is written from ReplayKit's
/// delivery queue, from the heartbeat timer's queue and from the lifecycle
/// callbacks — and two overlapping transactions break the seqlock three ways:
/// the sequence can settle *even* over a half-written body, a read-modify-write
/// can write back a body snapshotted before another thread's write and move
/// `currentFrameIdentity` backwards, and two interleaved closes can flip the
/// sequence's parity so that every later `load()` returns nil for the rest of the
/// session. `CaptureChannelTests.testTwoWriterThreadsCannotTearOrWedgeThePage`
/// measures all three. `writeLock` serialises the writers *within this process*,
/// which is all that is needed and is why it is an ordinary heap lock rather than
/// anything in the shared page. **Readers stay lock-free**: they never take it,
/// so a wedged or jetsam-killed writer still cannot block the keyboard, and the
/// cost on the writing side is about that of the memcpy it guards.
///
/// **Why no data protection above the default.** The page stays at the container
/// default, `.completeUntilFirstUserAuthentication`, on purpose: a mapped file
/// marked `.complete` becomes unreadable when the device locks, and touching a
/// mapping whose backing file has gone away is a `SIGBUS`, not an error return.
/// There is nothing in either page but timestamps, counters and a hash.
public final class SharedPage<Body>: @unchecked Sendable {

    /// How many times a read retries before giving up. The writer holds the page
    /// for the length of a memcpy, so one retry is already generous; giving up
    /// and returning nil rather than looping forever means a wedged writer
    /// cannot hang the keyboard's run loop.
    private static var readAttempts: Int { 16 }

    private let pointer: UnsafeMutableRawPointer
    private let bytes: Int
    private let descriptor: Int32
    private let bodyOffset = Int(CAPTURE_SEQ_HEADER_BYTES)

    /// Serialises the writing threads of this process. An `os_unfair_lock` behind
    /// `OSAllocatedUnfairLock`, which is the same lock with the pointer stability
    /// Swift does not promise for an `os_unfair_lock` held in a stored property.
    /// Uncontended it is a compare-and-swap; contended it parks the loser instead
    /// of spinning, which matters because one of the contenders is a 60 Hz media
    /// callback and another is a `.utility` timer.
    private let writeLock = OSAllocatedUnfairLock()

    public let isWritable: Bool

    private static var log: Logger {
        Logger(subsystem: "com.nitai.aikeyboard", category: "CaptureChannel")
    }

    /// Maps `url`, creating and zero-filling it when writable.
    ///
    /// Returns nil rather than throwing on every failure this can have, because
    /// every one of them means the same thing to a caller: there is no channel
    /// here. The container is out of reach (no entitlement, or a keyboard
    /// without Full Access), the file will not open, or it is too short to hold
    /// the page.
    public init?(url: URL, bytes: Int, writable: Bool) {
        precondition(
            MemoryLayout<Body>.size + Int(CAPTURE_SEQ_HEADER_BYTES) <= bytes,
            "\(Body.self) is \(MemoryLayout<Body>.size) bytes and does not fit a \(bytes)-byte page")
        precondition(MemoryLayout<Body>.alignment <= Int(CAPTURE_SEQ_HEADER_BYTES))

        let flags = writable ? (O_RDWR | O_CREAT) : O_RDONLY
        let opened = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return open(path, flags, S_IRUSR | S_IWUSR)
        }
        guard opened >= 0 else { return nil }

        if writable {
            // Grow to the full page before mapping. Mapping past the end of a
            // file and then touching those pages is a SIGBUS.
            var info = stat()
            if fstat(opened, &info) != 0 || info.st_size < off_t(bytes) {
                guard ftruncate(opened, off_t(bytes)) == 0 else {
                    close(opened)
                    return nil
                }
            }
        } else {
            var info = stat()
            guard fstat(opened, &info) == 0, info.st_size >= off_t(bytes) else {
                close(opened)
                return nil
            }
        }

        let protection = writable ? (PROT_READ | PROT_WRITE) : PROT_READ
        let mapped = mmap(nil, bytes, protection, MAP_SHARED, opened, 0)
        guard let mapped, mapped != MAP_FAILED else {
            close(opened)
            return nil
        }

        self.pointer = mapped
        self.bytes = bytes
        self.descriptor = opened
        self.isWritable = writable
    }

    deinit {
        munmap(pointer, bytes)
        close(descriptor)
    }

    /// A snapshot of the body, or nil if no settled snapshot was available.
    ///
    /// Nil is a real answer and callers must treat it as *no status*, never as
    /// an empty one: a zeroed `CaptureStatus` looks like a session that has
    /// never seen a frame, which the freshness gate correctly refuses, but
    /// inventing one hides a wedged writer behind a plausible value.
    ///
    /// Takes no lock, on purpose. See `writeLock`.
    public func load() -> Body? {
        for _ in 0..<Self.readAttempts {
            let opened = capture_seq_begin_read(pointer)
            guard opened & 1 == 0 else { continue }
            let body = pointer.load(fromByteOffset: bodyOffset, as: Body.self)
            if capture_seq_read_valid(pointer, opened) { return body }
        }
        return nil
    }

    /// Replaces the body in one seqlock transaction.
    public func store(_ body: Body) {
        precondition(isWritable, "store on a read-only page")
        writeLock.lock()
        defer { writeLock.unlock() }
        let opened = capture_seq_begin_write(pointer)
        pointer.storeBytes(of: body, toByteOffset: bodyOffset, as: Body.self)
        capture_seq_end_write(pointer, opened)
    }

    /// Read-modify-write, still one transaction.
    ///
    /// The read is taken from the mapping directly rather than through `load()`:
    /// the lock has already excluded every other writer, the only other process
    /// on this page is a reader, and going through the retry loop while holding
    /// an open sequence would deadlock against itself.
    ///
    /// `change` runs with the lock held and the sequence open, so it must not
    /// touch this page again — `writeLock` is an `os_unfair_lock` and is not
    /// recursive. Every caller here assigns fields and returns.
    public func mutate(_ change: (inout Body) -> Void) {
        precondition(isWritable, "mutate on a read-only page")
        writeLock.lock()
        defer { writeLock.unlock() }
        let opened = capture_seq_begin_write(pointer)
        var body = pointer.load(fromByteOffset: bodyOffset, as: Body.self)
        change(&body)
        pointer.storeBytes(of: body, toByteOffset: bodyOffset, as: Body.self)
        capture_seq_end_write(pointer, opened)
    }

    /// Zeroes the body.
    ///
    /// Used at session start so a page left behind by a previous session — or by
    /// a previous boot, after which the monotonic clock has restarted below
    /// every timestamp in it — cannot be mistaken for a live one.
    ///
    /// **Inside a transaction, and the sequence is not part of what it clears.**
    /// This used to `memset` the whole page, sequence number first, which is not a
    /// seqlock transaction at all: there is no odd interval for a reader to retry
    /// over, so a reader could validate a settled even sequence over a half-zeroed
    /// struct, and a reader whose open sequence happened to be zero would validate
    /// it against the zero this had just written. The sequence only has to be
    /// monotonic and even-when-settled, never low, so it keeps counting across a
    /// reset like any other write.
    public func reset() {
        precondition(isWritable, "reset on a read-only page")
        writeLock.lock()
        defer { writeLock.unlock() }
        let opened = capture_seq_begin_write(pointer)
        memset(pointer.advanced(by: bodyOffset), 0, bytes - bodyOffset)
        capture_seq_end_write(pointer, opened)
    }
}

// MARK: - The producing end

/// The capture process's end of the channel: it owns `status.bin`, reads
/// `intent.bin`, and is the only thing that ever writes a reading.
///
/// Nothing in here allocates per frame. `recordFrame` is called from inside
/// ReplayKit's delivery callback, so it does a seqlock write over a mapping and
/// returns.
public final class CaptureChannelWriter: @unchecked Sendable {

    private let statusPage: SharedPage<CaptureStatus>
    private let intentURL: URL
    private let readingURL: URL
    /// Opened on demand, because the file belongs to the other process. See
    /// `intent()`.
    private var intentPage: SharedPage<CaptureIntent>?
    private static let log = Logger(
        subsystem: "com.nitai.aikeyboard", category: "CaptureChannel")

    public init?() {
        guard
            CaptureChannel.prepareDirectory() != nil,
            let statusURL = CaptureChannel.statusURL,
            let intentURL = CaptureChannel.intentURL,
            let readingURL = CaptureChannel.readingURL,
            let statusPage = SharedPage<CaptureStatus>(
                url: statusURL, bytes: CaptureChannel.statusPageBytes, writable: true)
        else { return nil }

        self.statusPage = statusPage
        self.intentURL = intentURL
        self.readingURL = readingURL
    }

    /// Starts a session. Zeroes the page first, so nothing from a previous run
    /// survives into this one, then publishes the identity and the start time.
    @discardableResult
    public func begin(sessionID: UUID = UUID(), now: UInt64 = CaptureClock.now()) -> UUID {
        try? FileManager.default.removeItem(at: readingURL)
        statusPage.reset()
        var status = CaptureStatus()
        status.setSessionID(sessionID)
        status.startedAt = now
        status.heartbeatAt = now
        statusPage.store(status)
        Self.log.notice(
            "channel begin session=\(sessionID.uuidString, privacy: .public)")
        return sessionID
    }

    /// The 1 Hz liveness tick. Touches `heartbeatAt` and **nothing else** — not
    /// `lastFrameAt`, not the identity, not its timestamp. The heartbeat proves
    /// the process is alive; `lastFrameAt` proves delivery is alive; conflating
    /// them is how a wedged handler looks healthy.
    public func heartbeat(now: UInt64 = CaptureClock.now()) {
        statusPage.mutate { $0.heartbeatAt = now }
    }

    /// One delivered frame that was not sampled. Cheap, and it is what keeps the
    /// delivery-liveness condition true between samples.
    public func recordDelivery(now: UInt64 = CaptureClock.now()) {
        statusPage.mutate {
            $0.framesDelivered &+= 1
            $0.lastFrameAt = now
        }
    }

    /// One sampled frame. Identity and its timestamp are written together, in
    /// one transaction, here and nowhere else.
    public func recordFrame(_ fingerprint: FrameFingerprint, now: UInt64 = CaptureClock.now()) {
        statusPage.mutate {
            $0.framesDelivered &+= 1
            $0.framesSampled &+= 1
            $0.lastFrameAt = now
            $0.currentFrameIdentity = fingerprint.identity
            $0.currentFrameSampledAt = now
        }
    }

    public func setPaused(_ paused: Bool) {
        statusPage.mutate { $0.paused = paused ? 1 : 0 }
    }

    public func setDegraded(_ degraded: Bool) {
        statusPage.mutate { $0.degraded = degraded ? 1 : 0 }
    }

    public func count(_ counter: WritableKeyPath<CaptureStatus, UInt32>) {
        statusPage.mutate { $0[keyPath: counter] &+= 1 }
    }

    /// Records an ending. The heartbeat stops with it, so a reader that misses
    /// this still concludes `.lost` within three seconds.
    public func end(_ reason: ScreenContextEndReason, now: UInt64 = CaptureClock.now()) {
        statusPage.mutate {
            $0.endReasonRaw = reason.rawValue
            $0.heartbeatAt = now
        }
        try? FileManager.default.removeItem(at: readingURL)
        Self.log.notice("channel end reason=\(reason.rawValue, privacy: .public)")
    }

    public func status() -> CaptureStatus? { statusPage.load() }

    /// What the keyboard is asking for, or nil if it has never asked.
    ///
    /// Opened lazily and retried until it succeeds, because the file belongs to
    /// the other process and the two start in either order: a broadcast begun
    /// before the keyboard has ever appeared finds no `intent.bin`, and a
    /// mapping taken once at init would then stay nil for the whole session and
    /// silently ignore every Reply tap.
    public func intent() -> CaptureIntent? {
        if intentPage == nil {
            intentPage = SharedPage<CaptureIntent>(
                url: intentURL, bytes: CaptureChannel.intentPageBytes, writable: false)
        }
        return intentPage?.load()
    }

    /// Publishes a reading. Atomic, so the keyboard never reads half a JSON
    /// document, and explicitly protected no higher than the container default
    /// for the same reason the pages are not: a file the keyboard cannot open on
    /// a locked device is a feature that stops working in a pocket.
    public func publish(_ record: ScreenReadingRecord) throws {
        let data = try JSONEncoder().encode(record)
        try data.write(
            to: readingURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}

// MARK: - The consuming end

/// What a read of `status.bin` found. Three answers rather than two, and the
/// third one is a different thing to tell the user.
///
/// `.absent` means no producer has ever run against this container: the ordinary
/// starting state, and the strip says screen context is off. `.unsettled` means
/// the page is there and `load()` gave up — the sequence is odd and stayed odd
/// across all sixteen retries, which is what a producer killed *between*
/// `begin_write` and `end_write` leaves behind. Collapsing the two into nil is
/// how a jetsam kill came to render as "screen context is off", with no restart
/// offered, while the user's broadcast was still switched on.
public enum CaptureStatusReading: Equatable, Sendable {
    case absent
    case unsettled
    case settled(CaptureStatus)

    public var status: CaptureStatus? {
        guard case .settled(let status) = self else { return nil }
        return status
    }
}

/// The keyboard's end: it reads `status.bin` and the reading, and owns
/// `intent.bin`.
public final class CaptureChannelReader: @unchecked Sendable {

    private let statusURL: URL
    private let readingURL: URL
    private let intentPage: SharedPage<CaptureIntent>?
    /// Opened on demand, because the file belongs to the other process.
    private var statusPage: SharedPage<CaptureStatus>?

    /// Nil only when there is no App Group container: no entitlement, or a
    /// keyboard the user has not granted Full Access. That is a state to report
    /// to the user, not an error.
    ///
    /// A missing `status.bin` is **not** a reason to fail: it means no broadcast
    /// has ever run, which is the ordinary starting state, and the user can start
    /// one while the keyboard is already on screen.
    public init?() {
        guard
            CaptureChannel.prepareDirectory() != nil,
            let statusURL = CaptureChannel.statusURL,
            let intentURL = CaptureChannel.intentURL,
            let readingURL = CaptureChannel.readingURL
        else { return nil }

        self.statusURL = statusURL
        self.readingURL = readingURL
        self.intentPage = SharedPage<CaptureIntent>(
            url: intentURL, bytes: CaptureChannel.intentPageBytes, writable: true)
    }

    /// Retries the mapping until it succeeds, so a broadcast started while the
    /// keyboard is already up is picked up on the next 250 ms poll rather than
    /// the next time the keyboard is dismissed and shown again.
    public func status() -> CaptureStatusReading {
        if statusPage == nil {
            statusPage = SharedPage<CaptureStatus>(
                url: statusURL, bytes: CaptureChannel.statusPageBytes, writable: false)
        }
        guard let statusPage else { return .absent }
        guard let status = statusPage.load() else { return .unsettled }
        return .settled(status)
    }

    public func reading() -> ScreenReadingRecord? {
        guard let data = try? Data(contentsOf: readingURL) else { return nil }
        return try? JSONDecoder().decode(ScreenReadingRecord.self, from: data)
    }

    public func setKeyboardVisible(_ visible: Bool, now: UInt64 = CaptureClock.now()) {
        intentPage?.mutate {
            $0.keyboardVisible = visible ? 1 : 0
            $0.keyboardVisibleAt = now
        }
    }

    /// Raises the read request sequence and returns the new value. The record
    /// that answers this tap carries the same number.
    @discardableResult
    public func requestRead(now: UInt64 = CaptureClock.now()) -> UInt64 {
        guard let intentPage else { return 0 }
        var sequence: UInt64 = 0
        intentPage.mutate {
            $0.readNow &+= 1
            $0.readRequestedAt = now
            sequence = $0.readNow
        }
        return sequence
    }

    public func intent() -> CaptureIntent? { intentPage?.load() }
}
