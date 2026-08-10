import Foundation
import os

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

    private let directory: URL
    private let statusURL: URL
    private let readingURL: URL
    private let intentPage: SharedPage<CaptureIntent>?

    /// Opened on demand, because the file belongs to the other process, and
    /// **behind a lock for exactly the reason `CaptureChannelWriter.intentPage`
    /// is.** This class is declared `@unchecked Sendable`, which is a promise to
    /// every caller that two threads may be inside it at once; an unsynchronised
    /// lazy assignment of a class reference is not a wasted mapping but a torn
    /// store, and the loser's `SharedPage` can `munmap` and `close` while the
    /// winner is still reading through a pointer that came from it.
    ///
    /// Nothing exercises it today — every caller arrives on the main actor
    /// through `ScreenContextChannel` — and that is not the point. The writer
    /// side carried the identical pattern, was found to be wrong for the identical
    /// reason, and was fixed; leaving the mirror image unlocked means the promise
    /// in `@unchecked Sendable` is true only by accident of the current call
    /// graph.
    private let statusPage = OSAllocatedUnfairLock<SharedPage<CaptureStatus>?>(initialState: nil)

    /// Nil only when there is no App Group container: no entitlement, or a
    /// keyboard the user has not granted Full Access. That is a state to report
    /// to the user, not an error.
    ///
    /// A missing `status.bin` is **not** a reason to fail: it means no broadcast
    /// has ever run, which is the ordinary starting state, and the user can start
    /// one while the keyboard is already on screen.
    public convenience init?() {
        guard let directory = CaptureChannel.prepareDirectory() else { return nil }
        self.init(directory: directory)
    }

    /// Roots the channel somewhere other than the App Group container. See the
    /// writer's overload for why it exists.
    public init(directory: URL) {
        self.directory = directory
        self.statusURL = directory.appendingPathComponent("status.bin")
        self.readingURL = directory.appendingPathComponent("reading.json")
        self.intentPage = SharedPage<CaptureIntent>(
            url: directory.appendingPathComponent("intent.bin"),
            bytes: CaptureChannel.intentPageBytes, writable: true)
    }

    /// Unlinks a reading whose producer is gone, and says whether it took one.
    ///
    /// **The keyboard has to do this, because for most users nothing else will.**
    /// `reading.json` holds a sender's name and the text of their message, in a
    /// container that is backed up with the app. The producer deletes it in
    /// `begin()` and `end()`, neither of which a jetsam kill fires, and the full
    /// `CaptureChannel.sweep()` that covers that case runs once per cold launch
    /// of the *containing app* — which a user who only ever types on the keyboard
    /// may not open for weeks, or ever again after onboarding. That left the last
    /// message anyone read sitting on disk indefinitely.
    ///
    /// This is the narrow half of the sweep and deliberately not the whole of it:
    /// one `fileExists`, one page load, no directory enumeration. `sweep()` still
    /// owns the orphaned-directory half, which is genuinely the containing app's
    /// job — it has no memory cap and no latency budget, and the directories it
    /// removes are leftovers from an experiment rather than anything a live
    /// session can produce.
    ///
    /// `CaptureFreshness` is what stops a dead session's reading being *shown*;
    /// this is a separate obligation, and it holds whether or not anything would
    /// have believed the text.
    @discardableResult
    public func discardReadingOfADeadSession(now: UInt64 = CaptureClock.now()) -> Bool {
        CaptureChannel.discardReadingOfADeadSession(in: directory, now: now)
    }

    /// Retries the mapping until it succeeds, so a broadcast started while the
    /// keyboard is already up is picked up on the next 250 ms poll rather than
    /// the next time the keyboard is dismissed and shown again.
    public func status() -> CaptureStatusReading {
        // Mapped inside the lock, read outside it: the returned reference is a
        // strong one, so the page cannot be unmapped underneath the load, and a
        // seqlock read has no business holding a mutex.
        let page = statusPage.withLock { page -> SharedPage<CaptureStatus>? in
            if page == nil {
                page = SharedPage<CaptureStatus>(
                    url: statusURL, bytes: CaptureChannel.statusPageBytes, writable: false)
            }
            return page
        }
        guard let page else { return .absent }
        guard let status = page.load() else { return .unsettled }
        return .settled(status)
    }

    public func reading() -> ScreenReadingRecord? {
        guard let data = try? Data(contentsOf: readingURL) else { return nil }
        return try? JSONDecoder().decode(ScreenReadingRecord.self, from: data)
    }

    /// Says the keyboard is on screen and how much of the screen it covers.
    ///
    /// The height is not decoration beside the flag: it is what keeps the
    /// producer's fingerprint blind to our own animating panel, so it is written
    /// in the same transaction as the flag and cleared with it. See
    /// `CaptureIntent.ownUIHeightPermille`.
    public func setKeyboardVisible(
        _ visible: Bool, ownUIHeightFraction: Double = 0, now: UInt64 = CaptureClock.now()
    ) {
        intentPage?.mutate {
            $0.keyboardVisible = visible ? 1 : 0
            $0.keyboardVisibleAt = now
            $0.setOwnUIHeightFraction(visible ? ownUIHeightFraction : 0)
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

    /// Records a Reply tap the secure-field guard refused, without raising
    /// `readNow`. Written here rather than into `status.bin` because that page
    /// has one writing process and this is not it; see `CaptureIntent`.
    /// Records one secure-field decision.
    ///
    /// `refused` counts refusals. `unanswered` counts *every* decision where the
    /// host did not answer `isSecureTextEntry`, refused or not — which is the
    /// only way the open question stays measurable now that silence permits. If
    /// it counted silence only when it refused, a silent host would look
    /// identical to one that answered "not secure", and R14 would be unanswerable
    /// from the field.
    public func countSecureDecision(refused: Bool, unanswered: Bool) {
        guard refused || unanswered else { return }
        intentPage?.mutate {
            if refused { $0.refusedSecure &+= 1 }
            if unanswered { $0.refusedSecureUnknown &+= 1 }
        }
    }

    public func intent() -> CaptureIntent? { intentPage?.load() }
}
