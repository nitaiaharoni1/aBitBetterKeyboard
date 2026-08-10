import CaptureAtomics
import Foundation
import os

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
