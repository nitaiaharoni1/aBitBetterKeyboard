import Foundation
import os

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

    /// Opened on demand, because the file belongs to the other process, and
    /// **behind a lock for the same reason `status.bin`'s writers are**: `intent()`
    /// is called from `broadcastStarted`, on whatever queue ReplayKit runs the
    /// lifecycle callbacks, and from `serveReadRequest` on the delivery queue.
    /// ReplayKit does not document those to be the same queue. An unsynchronised
    /// lazy assignment across two threads is not merely a wasted mapping: the
    /// non-atomic store of a class reference can be observed half-written, and the
    /// loser's `SharedPage` can be released while the winner is reading through a
    /// pointer that came from it. See `intent()`.
    private let intentPage = OSAllocatedUnfairLock<SharedPage<CaptureIntent>?>(initialState: nil)

    /// True from `end()` until the next `begin()`. Guards `publish` — see it.
    private let hasEnded = OSAllocatedUnfairLock(initialState: false)

    private static let log = Logger(
        subsystem: "com.nitai.aikeyboard", category: "CaptureChannel")

    public convenience init?() {
        guard let directory = CaptureChannel.prepareDirectory() else { return nil }
        self.init(directory: directory)
    }

    /// Roots the channel somewhere other than the App Group container.
    ///
    /// The capture process always uses the container. This exists for tests:
    /// `AIKeyboardCoreTests` carries no App Group entitlement, so the container
    /// is unreachable there, and a consumer tested against a hand-built
    /// `CaptureStatus` would exercise neither the pages, nor the seqlock, nor the
    /// gate reading them.
    public init?(directory: URL) {
        guard
            let statusPage = SharedPage<CaptureStatus>(
                url: directory.appendingPathComponent("status.bin"),
                bytes: CaptureChannel.statusPageBytes, writable: true)
        else { return nil }

        self.statusPage = statusPage
        self.intentURL = directory.appendingPathComponent("intent.bin")
        self.readingURL = directory.appendingPathComponent("reading.json")
    }

    /// Starts a session. Zeroes the page first, so nothing from a previous run
    /// survives into this one, then publishes the identity and the start time.
    @discardableResult
    public func begin(sessionID: UUID = UUID(), now: UInt64 = CaptureClock.now()) -> UUID {
        hasEnded.withLock { $0 = false }
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

    // MARK: Device facts
    //
    // The capture process is the only thing that ever sees a real frame, and
    // until one of these is written by a phone every number this repo has about
    // ReplayKit is a prediction. They go in the page rather than only into the
    // log so the answer can be read off the app's own screen, with no cable and
    // no Mac. See `CaptureStatus`'s device-facts block.

    /// The shape of the first frame this session was handed. Written once —
    /// re-writing per frame would burn a seqlock transaction at 4 Hz to restate
    /// a constant, and a *changing* size is not something this records.
    public func recordFrameFormat(width: Int, height: Int, pixelFormat: UInt32) {
        statusPage.mutate {
            guard $0.frameWidth == 0 else { return }
            // Clamped rather than truncated: a dimension this does not fit is a
            // fact worth seeing as "at least 65535" rather than as a wrapped
            // number that looks plausible and is wrong.
            $0.frameWidth = UInt16(min(width, Int(UInt16.max)))
            $0.frameHeight = UInt16(min(height, Int(UInt16.max)))
            $0.pixelFormat = pixelFormat
        }
    }

    /// The current orientation, and the running set of every one seen.
    public func recordOrientation(_ orientation: FrameReduction.Orientation, raw: UInt8) {
        statusPage.mutate {
            $0.orientationRaw = raw
            $0.orientationsSeen |= orientation.bit
        }
    }

    /// Footprint in tenths of a megabyte. `baseline` is written once, at the
    /// start; `peak` only ever climbs, so a spike during a read survives being
    /// sampled again a moment later when it has already been released.
    public func recordFootprint(baselineMB: Double?, currentMB: Double?) {
        statusPage.mutate {
            if let baselineMB, $0.baselineFootprintTenthsMB == 0 {
                $0.baselineFootprintTenthsMB = Self.tenths(baselineMB)
            }
            if let currentMB {
                $0.peakFootprintTenthsMB = max($0.peakFootprintTenthsMB, Self.tenths(currentMB))
            }
        }
    }

    public func recordPause(resumed: Bool) {
        statusPage.mutate {
            // Saturating: "did it come back" is the question, and 255 answers it
            // as well as 300 would, while a wrap to 0 would answer it wrongly.
            if resumed {
                $0.resumeCount = $0.resumeCount == .max ? .max : $0.resumeCount + 1
            } else {
                $0.pauseCount = $0.pauseCount == .max ? .max : $0.pauseCount + 1
            }
        }
    }

    private static func tenths(_ megabytes: Double) -> UInt16 {
        UInt16(max(0, min((megabytes * 10).rounded(), Double(UInt16.max))))
    }

    /// Records an ending. The heartbeat stops with it, so a reader that misses
    /// this still concludes `.lost` within three seconds.
    ///
    /// **The flag is raised before the file is deleted, and that order is the
    /// point.** A read in flight publishes from its own queue; if it wrote between
    /// the deletion and the flag, the sender and the message would survive the
    /// session in a container that is backed up.
    ///
    /// **The first reason wins, and that is what keeps a diagnosis from being
    /// overwritten by a shrug.** `SampleHandler` ends a session it knows cannot
    /// work — no screen reader configured — by recording `.notConfigured` and then
    /// calling `finishBroadcastWithError:`. Whether iOS answers that with a
    /// `broadcastFinished()` is not documented anywhere in `RPBroadcastExtension.h`,
    /// and if it does, the unconditional write here would replace the reason the
    /// user can act on with `.stopped`, which names nothing. A session only ends
    /// once, and `begin()` zeroes the page, so ignoring the second call costs
    /// nothing and closes a race nobody can test from here.
    public func end(_ reason: ScreenContextEndReason, now: UInt64 = CaptureClock.now()) {
        hasEnded.withLock { $0 = true }
        var recorded = reason
        statusPage.mutate {
            if $0.endReason == .notEnded {
                $0.endReasonRaw = reason.rawValue
            } else {
                recorded = $0.endReason
            }
            $0.heartbeatAt = now
        }
        try? FileManager.default.removeItem(at: readingURL)
        Self.log.notice(
            """
            channel end reason=\(recorded.rawValue, privacy: .public) \
            asked=\(reason.rawValue, privacy: .public)
            """
        )
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
        intentPage.withLock { page in
            if page == nil {
                page = SharedPage<CaptureIntent>(
                    url: intentURL, bytes: CaptureChannel.intentPageBytes, writable: false)
            }
            // `load()` inside the lock rather than outside it. It takes no lock of
            // its own and its retry loop is bounded at sixteen, so the interval is
            // about that of the memcpy it reads — and doing it outside would mean
            // handing a mapping out of the lock that another thread may have
            // replaced.
            return page?.load()
        }
    }

    /// Publishes a reading. Atomic, so the keyboard never reads half a JSON
    /// document, and explicitly protected no higher than the container default
    /// for the same reason the pages are not: a file the keyboard cannot open on
    /// a locked device is a feature that stops working in a pocket.
    ///
    /// **Refused once the session has ended, and it deletes again afterwards.**
    /// This is a privacy rule, not tidiness. `publish` runs on the read queue and
    /// `end()` on ReplayKit's lifecycle queue, so a read that was already in
    /// flight when the user stopped the broadcast lands *after* `end()` deleted
    /// `reading.json` — and a sender's name and the text of their message then sit
    /// in the App Group container, which is backed up, until the next launch or
    /// the next broadcast. The flag closes the ordinary case; the second delete
    /// closes the window between the check and the write, where `end()` can still
    /// interleave.
    public func publish(_ record: ScreenReadingRecord) throws {
        guard !hasEnded.withLock({ $0 }) else { throw CaptureChannelError.sessionEnded }

        let data = try JSONEncoder().encode(record)
        try data.write(
            to: readingURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])

        if hasEnded.withLock({ $0 }) {
            try? FileManager.default.removeItem(at: readingURL)
            throw CaptureChannelError.sessionEnded
        }
    }
}

/// The one failure `CaptureChannelWriter` raises that is not a file-system error.
public enum CaptureChannelError: Error, LocalizedError {
    /// A reading finished after its session did. Nothing is published, because
    /// the message would outlive the session it was read in.
    case sessionEnded

    public var errorDescription: String? {
        "the capture session ended before the reading could be published"
    }
}
