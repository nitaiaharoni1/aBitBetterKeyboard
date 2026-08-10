import Foundation
import os

/// The only honest answer the containing app has to "is my keyboard installed,
/// and does it have Full Access".
///
/// There is no API for either question. `UIInputViewController.hasFullAccess`
/// exists, but it is readable only from inside the extension, and nothing at all
/// reports whether the user has added the keyboard. That is why the Home screen
/// carried three hardcoded booleans and told a phone's owner who had granted Full
/// Access that they had not.
///
/// What the app *can* do is look for something only a keyboard with Full Access
/// could have left behind. iOS hands a keyboard extension the App Group container
/// **only** once the user allows Full Access — the same fact `SharedContainer.url`,
/// `SharedStore.storage` and `CaptureChannel.isReachable` already rest on — so a
/// file written by the extension *into that container* is positive proof of three
/// things at once: the keyboard is installed, Full Access is on, and it has been
/// opened at least once.
///
/// **The absence of the file proves none of the three.** Not installed, installed
/// without Full Access, and installed but never switched to are indistinguishable
/// from the app's side, and there is no fourth signal that separates them.
/// `load()` returning nil is therefore a question the user has to answer by using
/// the keyboard once, not a "no" the app may render as an unticked box. Turning
/// nil into "not done" is the defect this type exists to remove, and turning it
/// into "done" would be the same defect pointing the other way.
///
/// **Why the flag has a timestamp beside it, and why a reader must consult it.**
/// `CaptureIntent.keyboardVisible` shipped as a bare flag and outlived the process
/// that wrote it. This record has the same shape and a sharper version of the same
/// hazard: `hasFullAccess` describes a run of the extension that has since ended,
/// the user can turn Allow Full Access off or remove the keyboard afterwards, and
/// **nothing can correct the file** — the keyboard loses the container in the same
/// instant it loses the permission, so the one process able to rewrite the record
/// is the one that can no longer reach it.
///
/// A reader that looks only at `hasFullAccess` therefore turns one revocation into
/// a permanent "Full Access ✓" over a keyboard whose cloud rewrites and key clicks
/// are dead, with no path back short of reinstalling. That is a worse lie than the
/// hardcoded `false` this type replaced: it over-claims, and it hides the cause of
/// a failure the user can see. So the confirmation **expires** —
/// `SetupState.isCurrent` puts a ceiling on the record's age and lets a stale one
/// fall back to `.unknown`, which is the honest answer and is what this type was
/// built to be able to say.
///
/// **Two values age this record, and neither works without the other.**
///
/// `recordedAt` is `CaptureClock`'s monotonic clock rather than a wall clock for
/// the reason every timestamp in this target is: a clock the user can set is a
/// clock that can make a stale record look current. `CLOCK_MONOTONIC_RAW` is
/// system-wide, so the app comparing its own *now* against a stamp the keyboard
/// took is exact — **within one boot**.
///
/// Across a boot it is worse than useless, and an earlier version of this comment
/// claimed the opposite. `CLOCK_MONOTONIC_RAW` on Darwin is nanoseconds *since
/// boot*, so it restarts near zero, and `CaptureClock.elapsed` saturates in only
/// one direction — it rejects a stamp larger than the current uptime and accepts
/// one smaller. A record stamped two hours into the previous boot is therefore
/// rejected for the first two hours of the next boot and then reads as freshly
/// written, for another whole `confirmationWindow`, after every restart, forever.
/// Restore-from-backup is the same path: the App Group container is in the iCloud
/// backup, so a new phone that has never had this keyboard enabled would tick as
/// soon as its uptime passed the old phone's stamp.
///
/// `bootIdentity` is what closes that. `CaptureChannel` has the same problem and
/// solves it with a session UUID, but that only works because its reader compares
/// against a *running* producer; here the writer is long gone and the reader has
/// nothing to compare to, so the identity has to be something the reader can
/// derive for itself. `kern.boottime` is that: both processes read the same value,
/// it changes at every restart and on every device, and a mismatch withholds the
/// tick rather than granting it.
public struct KeyboardPresence: Codable, Equatable, Sendable {

    /// `UIInputViewController.hasFullAccess`, as the extension read it in the run
    /// that wrote this record.
    ///
    /// Very nearly redundant with the file's own existence, and stored anyway
    /// because the two are different measurements and the app should believe the
    /// weaker of them: existence says the container was reachable, this says what
    /// UIKit reported in the same breath. The app ticks Full Access only when both
    /// agree, so a `false` here withholds the tick rather than the file's presence
    /// granting it — and a `false` never survives the next run of the keyboard
    /// that reads `true`, because a disagreeing flag always rewrites the record
    /// however recent it is.
    public let hasFullAccess: Bool

    /// `CaptureClock` nanoseconds, taken in the run that wrote this record.
    ///
    /// Only comparable against a *now* from the same boot — see the type's note.
    /// `bootIdentity` is what says whether that holds.
    public let recordedAt: UInt64

    /// Which boot of which device wrote this. See `KeyboardPresence.bootIdentity`.
    ///
    /// Non-optional with no default on purpose. A record written before this field
    /// existed fails to decode, `load` returns nil, and the card falls back to
    /// `.unknown` — which is the right migration rather than a missed one: a record
    /// with no boot identity is exactly a record whose age cannot be judged.
    public let bootIdentity: UInt64

    public init(hasFullAccess: Bool, recordedAt: UInt64, bootIdentity: UInt64) {
        self.hasFullAccess = hasFullAccess
        self.recordedAt = recordedAt
        self.bootIdentity = bootIdentity
    }

    // MARK: Which boot this is

    /// The wall-clock instant this device last booted, in microseconds, from
    /// `kern.boottime`. Zero when the sysctl could not be read.
    ///
    /// Used only for equality, never for arithmetic, which is what makes it safe to
    /// take from a wall clock: it is an identity, not an age. Anything that moves
    /// the system clock moves it too — Darwin keeps `boottime + uptime == now` — so
    /// setting the clock makes this boot look like a different one, the record stops
    /// matching, and the card falls to `.unknown` until the keyboard next runs. That
    /// is the safe direction, and it is the only direction a wall clock is allowed to
    /// push anything in this file.
    ///
    /// Zero is never a match, including against another zero: a boot identity that
    /// could not be read is not evidence that two records share a boot.
    /// `sysctlbyname` needs no entitlement and works inside an app extension.
    public static var bootIdentity: UInt64 {
        var boot = timeval()
        var size = MemoryLayout<timeval>.stride
        guard sysctlbyname("kern.boottime", &boot, &size, nil, 0) == 0 else { return 0 }
        return UInt64(boot.tv_sec) &* 1_000_000 &+ UInt64(boot.tv_usec)
    }

    // MARK: Where it lives

    static let fileName = "keyboard-presence.json"

    /// Nil in the keyboard until the user grants Full Access, which is the whole
    /// signal. See `SharedContainer.url`.
    public static var url: URL? {
        SharedContainer.url?.appendingPathComponent(fileName)
    }

    // MARK: Reading

    /// The record the keyboard left, or nil.
    ///
    /// Nil is ambiguous by construction — see the type's note. Callers that render
    /// it must say which three things they cannot tell apart.
    public static func load() -> KeyboardPresence? {
        guard let url else { return nil }
        return load(from: url)
    }

    /// Reads a record from a path of the caller's choosing.
    ///
    /// Public for the same reason `CaptureChannel.sweep(container:)` is:
    /// `AIKeyboardCoreTests` carries no App Group entitlement, so the real
    /// container is out of reach there and a presence test written against the
    /// singleton would prove nothing. Shipping code calls `load()`.
    public static func load(from url: URL) -> KeyboardPresence? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(KeyboardPresence.self, from: data)
    }

    // MARK: Writing

    /// How stale a record may be before the keyboard rewrites it.
    ///
    /// Nothing renders the age; the interval exists so the record cannot become
    /// write-once, and so that the stored flag is re-measured from time to time on
    /// a phone the user keeps for years. Long on purpose — the write is the only
    /// part of this that costs anything, and the keyboard launches many times a
    /// day.
    public static let refreshInterval = CaptureClock.nanoseconds(6 * 60 * 60)

    /// Leaves proof that this run of the keyboard reached the shared container.
    ///
    /// Returns true when the container now holds a record describing this run,
    /// whether or not this call was the one that wrote it. False means the
    /// container was out of reach, which in the keyboard means Full Access is off
    /// — there is nowhere to write and, correctly, nothing for the app to find.
    ///
    /// **Call it off the main thread.** It is one directory lookup, one small read
    /// and — usually — no write at all, but it is still file I/O and it must not
    /// sit between the user tapping the globe key and the keys appearing.
    @discardableResult
    public static func record(
        hasFullAccess: Bool, now: UInt64 = CaptureClock.now(),
        bootIdentity: UInt64 = KeyboardPresence.bootIdentity
    ) -> Bool {
        guard let url else { return false }
        return record(hasFullAccess: hasFullAccess, at: url, now: now, bootIdentity: bootIdentity)
    }

    /// Writes a record to a path of the caller's choosing. See `load(from:)` for
    /// why this is public.
    @discardableResult
    public static func record(
        hasFullAccess: Bool, at url: URL, now: UInt64 = CaptureClock.now(),
        bootIdentity: UInt64 = KeyboardPresence.bootIdentity
    ) -> Bool {
        let existing = load(from: url)
        guard
            needsWriting(
                over: existing, hasFullAccess: hasFullAccess, bootIdentity: bootIdentity, now: now)
        else { return true }

        let record = KeyboardPresence(
            hasFullAccess: hasFullAccess, recordedAt: now, bootIdentity: bootIdentity)
        guard let data = try? JSONEncoder().encode(record),
            (try? data.write(
                to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]))
                != nil
        else {
            log.error("presence write failed at \(url.lastPathComponent, privacy: .public)")
            return false
        }

        log.notice(
            "presence recorded fullAccess=\(hasFullAccess, privacy: .public) at=\(now, privacy: .public) boot=\(bootIdentity, privacy: .public)"
        )
        return true
    }

    /// How old a record may be and still be believed.
    ///
    /// Chosen against a one-sided cost. A confirmation that has expired too early
    /// costs a user who is correctly set up one honest sentence and one switch to
    /// the keyboard, which they were about to make anyway. A confirmation that
    /// never expires is a tick over a keyboard whose Full Access has been revoked,
    /// with the app asserting the opposite of a failure the user is looking at and
    /// no way to get out of it. Err short.
    ///
    /// Three days, and the floor under that number is `refreshInterval`. A record
    /// is rewritten only when a run of the keyboard finds it older than six hours,
    /// so a person who uses the keyboard constantly still carries a stamp up to
    /// six hours old; the ceiling has to clear that plus however long they go
    /// without reaching for this keyboard at all. Seventy-two hours leaves
    /// sixty-six of that, so two whole days of typing on somebody else's keyboard
    /// changes nothing on this screen. Any ceiling **below** `refreshInterval`
    /// would be incoherent — a correctly installed keyboard would flicker to
    /// `.unknown` in the gap between two writes — so the relationship between the
    /// two constants is asserted in `KeyboardPresenceTests`, not just described
    /// here. A week was the alternative and was rejected: it tolerates a week of
    /// the one error that has no way back.
    public static let confirmationWindow = CaptureClock.nanoseconds(72 * 60 * 60)

    /// Four reasons to write, and one not to.
    ///
    /// A record whose flag disagrees is rewritten however recent it is, which is
    /// what makes a `false` self-healing: a run that read `hasFullAccess` as false
    /// leaves a record the very next run can correct.
    ///
    /// **A record from another boot is rewritten however recent its stamp looks**,
    /// and that clause is not tidiness. A reader refuses a record whose boot
    /// identity is not this one, so without this the first six hours of uptime
    /// after every restart would leave a keyboard in active use unable to refresh
    /// the very record that is being refused — the user would type all morning and
    /// the card would keep saying it had not seen the keyboard.
    ///
    /// A stamp in the future is rewritten too, via `CaptureClock.elapsed` reporting
    /// `.max` for it. That is now a corrupt-record case rather than the reboot case
    /// it was written for; the boot identity handles reboots in both directions,
    /// and this only ever handled one of them.
    static func needsWriting(
        over existing: KeyboardPresence?, hasFullAccess: Bool, bootIdentity: UInt64, now: UInt64
    ) -> Bool {
        guard let existing else { return true }
        guard existing.hasFullAccess == hasFullAccess else { return true }
        guard existing.bootIdentity == bootIdentity else { return true }
        return CaptureClock.elapsed(since: existing.recordedAt, now: now) > refreshInterval
    }

    private static let log = Logger(
        subsystem: "com.nitai.aikeyboard", category: "KeyboardPresence")
}
