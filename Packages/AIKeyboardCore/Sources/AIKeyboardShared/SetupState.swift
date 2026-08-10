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
            : "On — key clicks work. The cloud model has not connected yet; it connects on its own "
                + "once this app has a network connection."
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
            // "have nowhere to run" was true when no backend existed anywhere and
            // is not any more: there is a server and the calls reach it. What it
            // used to turn them down for was a missing access token, which is why
            // this named a settings screen; attestation fills that in by itself
            // now, so the honest instruction is the network, not a destination.
            // See `fullAccessDetail`.
            : "The system key click sound, and the network a cloud model needs — including the connection "
                + "this app makes once to set that model up. Until it does, Hebrew Fix, Rewrite and Reply "
                + "are refused."
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
