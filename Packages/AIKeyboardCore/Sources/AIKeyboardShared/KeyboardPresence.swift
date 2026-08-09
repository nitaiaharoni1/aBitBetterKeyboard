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

// MARK: - Reading the record

/// What the app is entitled to say about one setup step.
///
/// Three states rather than a Bool, because two of the three things the setup card
/// reports cannot be queried at all and the old Bool rendered "not done" over an
/// answer the app did not have — a phone whose owner had granted Full Access was
/// shown an unticked box and a Fix button. `unknown` is that missing answer said
/// out loud: a question mark rather than an unticked box, and never a Fix button,
/// because nothing is known to be broken.
public enum SetupCheck: Equatable, Sendable {
    /// Measured, recently, and true.
    case confirmed
    /// Not measurable from here, or not measured recently enough to still be
    /// worth asserting. Not a failure.
    case unknown
    /// Measured, and the user has to change something. The only state that nags.
    case blocked
}

/// The microphone permission, without AVFoundation.
///
/// `AVAudioApplication.recordPermission` is what the app actually reads; this is
/// the same three answers in a form this target can hold, because
/// `AIKeyboardShared` is linked on its own by the broadcast upload extension and
/// must not pull AVFoundation into a process capped at ~50 MB. The app maps one to
/// the other in a single switch.
public enum MicrophonePermission: Equatable, Sendable {
    case undetermined
    case denied
    case granted
}

/// The setup facts and the only honest reading of each.
///
/// A value type with no I/O in it on purpose: the two measurements are taken by
/// the app — one file read, one AVFoundation property — and everything after that
/// is a decision that can be pinned by a test. It lives here rather than beside the
/// SwiftUI because the app target has no unit-test host, and the mapping *is* the
/// fix: `nil → .unknown` is the whole difference between this screen and the three
/// hardcoded booleans it replaced.
public struct SetupState: Equatable, Sendable {

    /// The keyboard's own proof that it exists and has Full Access, or nil. See
    /// `KeyboardPresence` for why nil is a question and not a "no".
    public var presence: KeyboardPresence?

    public var microphone: MicrophonePermission

    /// `CaptureClock` nanoseconds, taken when the two measurements above were.
    /// Stored rather than read on demand so that a rendering pass cannot change
    /// the answer half way down the card, and so a test can place a record at any
    /// age it likes.
    public var now: UInt64

    /// This boot, to compare the record's against. Stored for the same reason
    /// `now` is: it makes every case in the truth table reachable from a test.
    public var bootIdentity: UInt64

    /// Whether `BackendTransport.configured()` would answer with a transport.
    ///
    /// **A third measurement, because two surfaces were asserting the opposite of
    /// the truth.** Full Access is what gives the keyboard a network; it is not
    /// what gives it somewhere to send. With no backend URL in the shared store
    /// there is no cloud engine at all, so "cloud rewrites work" printed under a
    /// green tick was wrong for every stock install — and wrong in the one place
    /// the user goes to find out whether they are set up. Measured by the app in
    /// `SetupState.current()`, in the same breath as the other two, and stored here
    /// rather than read on demand for the reason `now` is.
    public var cloudConfigured: Bool

    public init(
        presence: KeyboardPresence? = nil,
        microphone: MicrophonePermission = .undetermined,
        cloudConfigured: Bool = false,
        now: UInt64 = CaptureClock.now(),
        bootIdentity: UInt64 = KeyboardPresence.bootIdentity
    ) {
        self.presence = presence
        self.microphone = microphone
        self.cloudConfigured = cloudConfigured
        self.now = now
        self.bootIdentity = bootIdentity
    }

    /// Whether the record is recent enough to still be worth asserting.
    ///
    /// Two conditions, and each covers a case the other cannot see.
    ///
    /// **Same boot.** `recordedAt` is uptime, so it is only comparable against a
    /// *now* from the same boot; a stamp from a previous boot is a smaller number
    /// than the current uptime for most of every boot and would read as freshly
    /// written. Requiring the identity to match makes a restart mean what it should
    /// — nothing has checked the permission since — and makes a container restored
    /// from another phone's backup mean the same thing. A boot identity of zero
    /// never matches, so a device whose `kern.boottime` cannot be read simply never
    /// claims.
    ///
    /// **Within the window.** A phone can stay up for weeks, and Full Access can be
    /// revoked at any point in them, so age still has to expire a record inside one
    /// boot.
    public var isCurrent: Bool {
        guard let presence, bootIdentity != 0, presence.bootIdentity == bootIdentity else {
            return false
        }
        return CaptureClock.elapsed(since: presence.recordedAt, now: now)
            <= KeyboardPresence.confirmationWindow
    }

    /// Only the extension's own process could have written the record, so a
    /// current record settles this even when the flag inside it does not.
    public var keyboardAdded: SetupCheck { isCurrent ? .confirmed : .unknown }

    public var fullAccess: SetupCheck {
        isCurrent && presence?.hasFullAccess == true ? .confirmed : .unknown
    }

    public var microphoneAccess: SetupCheck {
        switch microphone {
        case .granted: return .confirmed
        case .denied: return .blocked
        case .undetermined: return .unknown
        }
    }

    public var keyboardAddedDetail: String {
        keyboardAdded == .confirmed
            ? "Available in every app"
            : "Settings › General › Keyboard › Keyboards › Add New Keyboard"
    }

    /// **Only claims the cloud when there is one.** This read "On — cloud rewrites
    /// and key clicks work" whenever Full Access was confirmed, which on a stock
    /// install is the sentence a user sees immediately before every Hebrew rewrite
    /// they try fails for want of the very thing it says is working. Full Access
    /// buys the network; it does not buy somewhere to send.
    public var fullAccessDetail: String {
        guard fullAccess == .confirmed else { return "Typing and on-device AI work without it" }
        return cloudConfigured
            ? "On — cloud rewrites and key clicks work"
            : "On — key clicks work. Cloud rewrites need a cloud model: \(BackendTransport.settingsPath)."
    }

    /// What onboarding's Full Access step lists under "What it turns on".
    ///
    /// Here rather than in the view for the reason the rest of this type is: it is
    /// a sentence chosen by a state, the app target has no test host, and the
    /// version it replaces promised cloud rewrites to a user who had no cloud
    /// model and no idea one was needed.
    public var fullAccessTurnsOn: String {
        cloudConfigured
            ? "Cloud rewrites for languages the on-device model cannot handle, and the system key click sound."
            : "The system key click sound, and the network a cloud model needs. None is set up yet, so Hebrew "
                + "Fix, Rewrite and Reply have nowhere to run — \(BackendTransport.settingsPath) is where one goes."
    }

    /// What onboarding's Full Access step lists under "Works without it".
    ///
    /// **The sentence it replaces cost the user the choice they had just made.**
    /// It read "Typing, autocorrect, predictions and emoji all run locally. Full
    /// Access is only for the cloud fallback", which is false twice over: iOS hands
    /// a keyboard extension the shared container only once Full Access is granted,
    /// so `SharedContainer.url` is nil, `SharedStore` falls back to `.standard`,
    /// and **every** setting the app wrote is invisible to the keyboard — including
    /// the language list picked two screens earlier, which leaves a French-only
    /// user with an English/Hebrew keyboard and no way to change it from inside
    /// one. And the row directly above it in the same card says Full Access turns
    /// on the key click sound, which "only for the cloud fallback" contradicts.
    ///
    /// A constant rather than a state-dependent sentence: the row is a
    /// hypothetical, and the hypothetical is the same whether or not the switch is
    /// on yet.
    public static let worksWithoutFullAccess =
        "Typing, autocorrect, predictions and emoji run on the device either way. Nothing that crosses "
        + "between the two does: iOS only lets the keyboard read this app's storage once Full Access is "
        + "on, so without it the languages you picked, your tone and your personal dictionary never "
        + "reach it. It falls back to English and Hebrew, with no key click and no cloud model."

    /// The same consequence, said where the choice is made rather than two screens
    /// later. Shown beside the language list only while Full Access is unconfirmed,
    /// which is the only state in which it is news.
    public static let languagesNeedFullAccess =
        "The keyboard can only read this list once Full Access is on. Until then it types English and "
        + "Hebrew whatever is chosen here."

    public var microphoneDetail: String {
        switch microphoneAccess {
        case .confirmed: return "Allowed for this app"
        case .blocked: return "Blocked in Settings"
        case .unknown: return "Not asked yet — dictation is still a demo"
        }
    }

    /// The two things the keyboard actually needs. The microphone is deliberately
    /// not one of them: a keyboard extension cannot open the microphone at all,
    /// with or without Full Access, so counting it would leave every user one step
    /// short of a checklist they cannot finish — which is the same nag this card is
    /// being fixed for.
    public var requirementCount: Int { 2 }

    public var confirmedRequirements: Int {
        [keyboardAdded, fullAccess].filter { $0 == .confirmed }.count
    }

    public var isReady: Bool { confirmedRequirements == requirementCount }

    /// What to say when a requirement is unconfirmed.
    ///
    /// Three shapes, because the app can distinguish three situations and telling
    /// somebody to do the thing they have just done is the defect this card is
    /// being fixed for.
    ///
    /// With **no record**, three causes are indistinguishable: never added, added
    /// without Full Access, added but never switched to. The most common of them by
    /// far is the middle one — a keyboard without Full Access writes nothing, so it
    /// looks exactly like a keyboard that was never added — which is why the words
    /// have to name the permission rather than only say "switch to it once".
    ///
    /// With a **stale record** the keyboard was seen and has not been seen since,
    /// so the honest thing is to say the tick expired and name what would have
    /// caused it if it is not simply disuse.
    ///
    /// With a **current record reporting no Full Access** the app knows which case
    /// it is, and says only that.
    public var unresolvedExplanation: String? {
        guard !isReady else { return nil }
        if presence != nil, isCurrent {
            return "The keyboard has run, and it reported Full Access as off. Turn on Allow Full "
                + "Access under Settings › General › Keyboard › Keyboards › AI Keyboard."
        }
        if presence != nil {
            return "It is a few days since the keyboard last checked in, or the phone has "
                + "restarted since, so this is no longer something we can promise. Switch to AI "
                + "Keyboard in any app once to check again — if it does not tick, the keyboard "
                + "has been removed or Allow Full Access turned off."
        }
        return "iOS never tells an app either of these. The keyboard has to be added and have "
            + "Allow Full Access turned on, both under Settings › General › Keyboard › "
            + "Keyboards. Switch to it in any app once afterwards and they will tick themselves."
    }
}
