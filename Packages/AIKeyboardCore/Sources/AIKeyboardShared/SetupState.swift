import Foundation

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

    /// Whether the user has confirmed, in the app, that they switched to AI
    /// Keyboard with the globe key.
    ///
    /// **Self-reported, unlike everything else in this type.** iOS gives the
    /// containing app no way to learn which keyboard is on screen in another
    /// process, so the closest measurable signal is `KeyboardPresence` — the
    /// keyboard ran at all — and this flag is the user's own answer to the one
    /// question presence cannot ask. It rides along here so Home and onboarding
    /// render one list of rows from one value, and it is deliberately *not* one
    /// of the counted requirements: the two measured steps decide readiness.
    public var switchAcknowledged: Bool

    public init(
        presence: KeyboardPresence? = nil,
        microphone: MicrophonePermission = .undetermined,
        cloudConfigured: Bool = false,
        switchAcknowledged: Bool = false,
        now: UInt64 = CaptureClock.now(),
        bootIdentity: UInt64 = KeyboardPresence.bootIdentity
    ) {
        self.presence = presence
        self.microphone = microphone
        self.cloudConfigured = cloudConfigured
        self.switchAcknowledged = switchAcknowledged
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

    /// The globe-key switch, as a check. `unknown`, never `blocked`: the app has
    /// no way to know the user has *not* done it, only that they have not said
    /// they did — and an unticked box is not an accusation.
    public var keyboardSwitched: SetupCheck {
        switchAcknowledged ? .confirmed : .unknown
    }

    public var keyboardSwitchedDetail: String {
        switchAcknowledged
            ? "Confirmed — you switched with the globe key"
            : "Tap the globe key in any app and choose aBitBetterKeyboard"
    }

    /// **Only claims the cloud when there is one.** This read "On — cloud rewrites
    /// and key clicks work" whenever Full Access was confirmed, which on a stock
    /// install is the sentence a user sees immediately before every Hebrew rewrite
    /// they try fails for want of the very thing it says is working. Full Access
    /// buys the network; it does not buy somewhere to send.
    /// **Stopped naming a destination when there stopped being anything to do
    /// there.** This used to end at `settingsPath`, because the way to be
    /// unconfigured was an address with no access token beside it and that screen
    /// held the box to paste one into. `AppAttestation` fills the bearer now and
    /// the box is gone from Release, so the remaining ways to be false are: the
    /// app has never had a network since install, so attestation never ran, or the
    /// session token it wrote has expired. Neither is fixed by walking to a
    /// settings screen, and sending somebody to one that offers them nothing is
    /// the failure this type exists to stop. It connects itself, so the sentence
    /// says so.
    public var fullAccessDetail: String {
        guard fullAccess == .confirmed else { return "Typing and on-device AI work without it" }
        return cloudConfigured
            ? "On — cloud rewrites and key clicks work"
            : "On — key clicks work. aBitBetterKeyboard has not connected yet; it connects on its own "
                + "once this app has a network connection."
    }

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
        case .unknown: return "Asked when you start a dictation session"
        }
    }

    /// The two things the keyboard actually needs. The microphone is deliberately
    /// not one of them, and still is not now that dictation records for real: a
    /// keyboard extension cannot open the microphone with or without Full Access,
    /// so the permission belongs to the *app*, is asked for when a session starts,
    /// and is not a step between somebody and a working keyboard. Counting it would
    /// leave every user who does not dictate one short of a checklist they have
    /// finished.
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
                + "Access under Settings › General › Keyboard › Keyboards › aBitBetterKeyboard."
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
