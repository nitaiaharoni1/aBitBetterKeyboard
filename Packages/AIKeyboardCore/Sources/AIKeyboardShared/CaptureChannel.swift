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

    /// Puts the channel back to "no session has ever run", in place.
    ///
    /// **In place rather than by deleting the files**, which is not a style
    /// preference: another process may already have these pages mapped, and
    /// unlinking a mapped file leaves that process reading an inode nobody will
    /// ever write to again — a channel that looks alive and is not. Zeroing
    /// through the seqlock is seen by every reader on the next load.
    ///
    /// Only `-uiTestReset` calls this. A capture session never does: it calls
    /// `CaptureChannelWriter.begin()`, which zeroes the same page and then
    /// publishes an identity.
    public static func clear() {
        sweep()
        guard prepareDirectory() != nil, let statusURL, let intentURL, let readingURL else {
            return
        }
        SharedPage<CaptureStatus>(url: statusURL, bytes: statusPageBytes, writable: true)?.reset()
        SharedPage<CaptureIntent>(url: intentURL, bytes: intentPageBytes, writable: true)?.reset()
        try? FileManager.default.removeItem(at: readingURL)
    }

    /// Takes out of the shared container the things nothing will ever read again.
    ///
    /// Two jobs, and the rule they share is the one `clear()` obeys: **never
    /// unlink a file another process may have mapped.**
    ///
    /// **Orphaned channel directories.** Shipping code opens `channel/` and
    /// nothing else, but the container on this machine also holds
    /// `channel-com.nitai.aikeyboard/` and
    /// `channel-com.nitai.aikeyboard.keyboard/`, left by an experiment that
    /// rooted the channel per process. No code has opened either since, so
    /// unlinking them cannot strand a reader the way unlinking `channel/status.bin`
    /// would — which is the whole reason `clear()` zeroes in place instead. The
    /// match is by prefix rather than by naming those two, so the next variant of
    /// the same mistake cleans itself up as well.
    ///
    /// **A reading whose producer is gone.** `reading.json` holds a sender and
    /// the text of somebody's message, in a container that is backed up with the
    /// app, and the producer deletes it only in `begin()` and `end()` — neither of
    /// which a jetsam kill fires. `CaptureFreshness` is what stops it being
    /// *shown*: its session no longer matches, its heartbeat is stale, and after
    /// a reboot the monotonic clock restarts below every timestamp in the page so
    /// `CaptureClock.elapsed` calls them infinitely old. This is a separate
    /// obligation from that one — the text should not outlive the session it was
    /// read in, whether or not anything would have believed it.
    ///
    /// Called by the containing app, which has no memory cap and no keyboard's
    /// latency budget. **Never call it from `AIKeyboardBroadcast`**: a directory
    /// enumeration inside a process capped at ~50 MB buys nothing, and the
    /// producer's own `begin()` already clears what it owns.
    ///
    /// **This is not the only place the reading half runs, and it must not be.**
    /// The containing app is launched once during onboarding and then, for a user
    /// who only ever types on the keyboard, possibly never again — so a sweep
    /// that lives only here leaves the last message anyone read on disk
    /// indefinitely. The keyboard runs the narrow half itself, every time it
    /// starts watching, through `CaptureChannelReader.discardReadingOfADeadSession`.
    /// The two halves are split by cost, not by owner: unlinking one file whose
    /// producer is provably gone is cheap enough for any process, enumerating a
    /// directory is not.
    public static func sweep(now: UInt64 = CaptureClock.now()) {
        guard let container = SharedContainer.url else { return }
        let removed = sweep(container: container, now: now)
        guard !removed.isEmpty else { return }
        log.notice("channel sweep removed=\(removed.joined(separator: ","), privacy: .public)")
    }

    /// Sweeps a container other than the App Group's, and says what it took.
    ///
    /// Public for the same reason `CaptureChannelWriter.init(directory:)` is:
    /// `AIKeyboardCoreTests` carries no App Group entitlement, so the real
    /// container is out of reach there and a sweep tested against a mock would
    /// exercise neither the directory rule nor the liveness question underneath
    /// the reading. Shipping code always goes through `sweep()`.
    @discardableResult
    public static func sweep(container: URL, now: UInt64 = CaptureClock.now()) -> [String] {
        let manager = FileManager.default
        var removed: [String] = []

        let contents =
            (try? manager.contentsOfDirectory(
                at: container, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        for entry in contents {
            let name = entry.lastPathComponent
            guard name.hasPrefix("channel"), name != "channel" else { continue }
            guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            else { continue }
            if (try? manager.removeItem(at: entry)) != nil { removed.append(name) }
        }

        let live = container.appendingPathComponent("channel", isDirectory: true)
        if discardReadingOfADeadSession(in: live, now: now) { removed.append("channel/reading.json") }
        return removed
    }

    /// True when a reading was removed.
    ///
    /// "Is the producer alive" is `CaptureFreshness`'s question everywhere else;
    /// this is the one caller that has to ask it with no record to judge. Public
    /// because the keyboard needs the narrow half of the sweep on its own — see
    /// `CaptureChannelReader.discardReadingOfADeadSession` for why the containing
    /// app's once-per-launch call was not enough.
    public static func discardReadingOfADeadSession(
        in directory: URL, now: UInt64 = CaptureClock.now()
    )
        -> Bool
    {
        let readingURL = directory.appendingPathComponent("reading.json")
        guard FileManager.default.fileExists(atPath: readingURL.path) else { return false }

        let status = SharedPage<CaptureStatus>(
            url: directory.appendingPathComponent("status.bin"),
            bytes: statusPageBytes, writable: false)?.load()
        // Nil covers three cases and all three mean the same thing here: no page,
        // a page too short to be one, and a page a killed producer left mid-write.
        let isAlive =
            status.map {
                $0.sessionID != nil && $0.endReason == .notEnded
                    && CaptureClock.elapsed(since: $0.heartbeatAt, now: now)
                        <= CaptureFreshness.heartbeatWindow
            } ?? false
        guard !isAlive else { return false }
        return (try? FileManager.default.removeItem(at: readingURL)) != nil
    }

    private static let log = Logger(
        subsystem: "com.nitai.aikeyboard", category: "CaptureChannel")

    static func prepareDirectory() -> URL? {
        guard let directory = directoryURL else { return nil }
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        return directory
    }
}
