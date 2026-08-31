import Foundation
import Combine
import os

/// One decode of a stored JSON blob, kept against the exact bytes it was made
/// from.
///
/// **The key is the stored `Data` and never a timestamp, a flag or a "first
/// time" test**, for the same reason `PersonalLanguageModel`'s file stamp is the
/// file rather than a clock: the app is a second process and can rewrite a
/// setting at any moment, so the only question that is safe to ask is "are these
/// the same bytes I decoded". Everything the `stored*` accessors promise about
/// freshness survives — `UserDefaults` is still read at the moment of use, and a
/// value the app changed is different bytes and therefore a real decode.
///
/// What it removes is repetition. The keyboard decoded the stored layout **five
/// times** before its first frame — `load()` and `KeyboardController.init` and
/// `reloadCustomization()` in `viewDidLoad`, then `load()` and
/// `reloadCustomization()` again in `viewWillAppear` — each one running
/// `JSONDecoder`, the preset refresh, the globe repair and `LayoutValidator`
/// over bytes that had not moved. Comparing them is a memcmp.
///
/// Locked because `SharedStore` is not bound to an actor. Every current reader
/// is on the main one; the lock is what stops that being load-bearing.
final class StoredDecode<Value> {

    private let lock = NSLock()
    private var data: Data?
    private var value: Value?

    /// The decoded value for these bytes, decoding only if they are not the
    /// bytes already held.
    ///
    /// An absent key caches too, and deliberately: nil bytes are a fact about
    /// the store like any other, and re-deciding "there is no stored layout"
    /// costs the same walk through the preset table as deciding it once.
    func value(for data: Data?, decode: () -> Value) -> Value {
        lock.lock()
        defer { lock.unlock() }
        if let value, self.data == data { return value }
        let decoded = decode()
        self.data = data
        self.value = decoded
        return decoded
    }
}

/// Settings the app writes and the keyboard reads.
///
/// Both targets carry the App Group entitlement, so `UserDefaults(suiteName:)`
/// resolves to one plist inside the shared container and a change made in the
/// app is visible to the keyboard extension.
public final class SharedStore: ObservableObject {

    public static let appGroupIdentifier = SharedContainer.appGroupIdentifier

    public static let shared = SharedStore()

    /// Where this instance actually persists. Probed at init, never assumed.
    public enum Storage: String {
        /// The App Group suite. The app and the keyboard see one store.
        case appGroup
        /// This process's own defaults, because the shared container was out of
        /// reach. Anything written here is invisible to the other process.
        case processLocal
    }

    /// `.processLocal` means the two processes are *not* sharing state, and
    /// anything that round-trips through this store between the app and the
    /// keyboard will quietly fail.
    public let storage: Storage

    let defaults: UserDefaults

    /// The store the two processes actually share, for callers that need
    /// `UserDefaults` itself rather than one of the typed accessors below.
    ///
    /// Exposed because the alternative is worse: a caller reaching for
    /// `.standard` gets a store that works perfectly in the app, is private to
    /// the extension in the keyboard, and fails silently in exactly one of the
    /// two processes. `BackendTransport.configured` shipped that bug.
    public var userDefaults: UserDefaults { defaults }

    /// Set for the length of `load()`. See `persist(_:forKey:)`.
    ///
    /// **Unsynchronised, and that is not a new hazard.** Two concurrent `load()`
    /// calls would race this flag and one could suppress the other's writes —
    /// but two concurrent `load()` calls already race all twenty-two
    /// `@Published` assignments underneath it, which is worse. Every caller is on
    /// the main thread: `AIKeyboardApp`'s `onAppear`, `viewDidLoad` and
    /// `viewWillAppear` in `KeyboardViewController`, and one test. Adding a lock
    /// here would suggest the rest of the function is safe off it.
    var isLoading = false

    /// The two settings held as JSON rather than as a scalar, and therefore the
    /// two whose reads cost a decode. Internal rather than private so
    /// `SharedStore+Layout.swift` can reach the first. See `StoredDecode`.
    let layoutCache = StoredDecode<(layout: KeyboardCustomization, migrated: Bool)>()
    let copyclipCache = StoredDecode<(record: CopyclipRecord, migrated: Bool)>()

    /// The `didSet` write-back, skipped while `load()` is the one assigning.
    ///
    /// **`load()`'s doc comment claimed for its whole life that it read without
    /// firing these writes, and `didSet` fires on every assignment outside
    /// `init`, so the opposite was true.** Each `load()` assigned twenty-two
    /// published properties and each one wrote straight back the value it had
    /// just read: twenty-two `UserDefaults` writes, two of them full JSON
    /// *encodes* re-serialising the layout and the copyclip record a line after
    /// deserialising them. The keyboard calls `load()` twice on a cold launch,
    /// in `viewDidLoad` and again in `viewWillAppear`, both before the first
    /// frame.
    ///
    /// **It suppresses the write and nothing else**, which is why this is a
    /// helper rather than a guard at the top of each `didSet`: `brandPalette`'s
    /// `didSet` also puts the accent into `Theme`, and that half has to run on a
    /// load or the process draws the shipped colour over the user's.
    ///
    /// The three assignments in `load()` that are genuine **migrations** write
    /// themselves, explicitly, at the end of it — see `persistMigrations()`. A
    /// wholesale suppression without that would be a migration that silently
    /// stopped sticking, which is the trap NIT-186 names.
    func persist(_ value: Any?, forKey key: String) {
        guard !isLoading else { return }
        defaults.set(value, forKey: key)
    }

    static let log = Logger(subsystem: "com.nitai.aikeyboard", category: "SharedStore")

    private init() {
        // `UserDefaults(suiteName:)` hands back a usable object whether or not
        // this process is entitled to the group, which is exactly how the old
        // `?? .standard` fallback could look successful while each process
        // talked to its own store. Asking the container manager for the group's
        // directory is the question that actually has a false answer: it is nil
        // without the entitlement, and nil in the keyboard until the user grants
        // Full Access.
        if SharedContainer.url != nil, let suite = UserDefaults(suiteName: Self.appGroupIdentifier) {
            defaults = suite
            storage = .appGroup
        } else {
            defaults = .standard
            storage = .processLocal
            Self.log.error(
                """
                App Group \(Self.appGroupIdentifier, privacy: .public) is unreachable — \
                settings are private to this process and will not reach the keyboard.
                """
            )
        }
    }

    /// Internal rather than private so `ToneSetting.swift`'s two accessors can
    /// name their keys here instead of keeping a second copy of the strings. A
    /// setting stored under a string that exists in two files is a setting
    /// `resetToDefaults()` will eventually stop clearing.
    enum Key {
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let enabledLanguages = "enabledLanguages"
        /// `KeyboardLanguage.rawValue` for the language the user last put the
        /// keyboard on themselves, and the one the next launch opens on. See
        /// `storedOpeningLanguage`.
        static let lastLanguage = "lastLanguage"
        /// The pre-three-way boolean. Read only to migrate an existing install
        /// onto `autocorrectLevel`; nothing writes it any more. See
        /// `storedAutocorrectLevel`.
        static let autocorrect = "autocorrect"
        static let autocorrectLevel = "autocorrectLevel"
        static let completeOnIdle = "completeOnIdle"
        static let spaceOnIdle = "spaceOnIdle"
        static let idleDelayMs = "idleDelayMs"
        static let autocapitalise = "autocapitalise"
        static let predictions = "predictions"
        static let haptics = "haptics"
        static let hapticStrength = "hapticStrength"
        static let keySounds = "keySounds"
        static let groupedLevel = "groupedLevel"
        static let defaultTone = "defaultTone"
        /// The two `BackendTransport.configured` reads. It declares them inline in
        /// `AIKeyboardShared`, which cannot see this enum, so they are spelled
        /// twice on purpose and
        /// `BackendTransportSuiteTests.testConfiguredReadsWhicheverStoreItIsGiven`
        /// is what fails if the two spellings ever part.
        static let cloudBackendURL = "cloudBackendURL"
        static let cloudBackendToken = "cloudBackendToken"
        static let cloudSessionToken = "cloudSessionToken"
        static let cloudAIProcessingAllowed = BackendTransport.cloudAIProcessingAllowedKey
        static let attestKeyId = "attestKeyId"
        static let attestationReport = "attestationReport"
        static let attestationCheckedAt = "attestationCheckedAt"
        static let customToneInstruction = "customToneInstruction"
        static let prefersCustomTone = "prefersCustomTone"
        static let personalDictionary = "personalDictionary"
        static let isSubscribed = "isSubscribed"
        static let screenContextAllowed = "screenContextAllowed"
        static let keyboardLayout = "keyboardLayout"
        static let recentEmoji = "recentEmoji"
        static let emojiSkinTone = "emojiSkinTone"
        static let copyclipHistory = "copyclipHistory"
        static let hasAcknowledgedKeyboardSwitch = "hasAcknowledgedKeyboardSwitch"
        static let brandPalette = "brandPalette"
        /// A Unix timestamp written by the keyboard when it wants the app to start
        /// dictation. The app consumes it exactly once and refuses stale requests.
        static let dictationHandoffRequest = "dictationHandoffRequest"
        /// `KeyboardLanguage.rawValue` for whichever layout the keyboard was
        /// showing the last time it opened a dictation utterance. Written by the
        /// keyboard, read by the app — see `storedDictationLanguage`.
        static let dictationActiveLanguage = "dictationActiveLanguage"
    }

    /// Keys this store used to write and no longer reads.
    ///
    /// **A deleted property is not a deleted setting.** `screenContextCloudReplies`
    /// backed a "Use the cloud for replies" toggle that promised switching it off
    /// would keep screen reading on the device. No code ever read it, and the
    /// property is gone rather than fixed, because reading is cloud-only in the
    /// capture flow and the toggle promised something no code could keep. The
    /// *value* it wrote is still in the App Group plist of every install that ran
    /// that build, which is the same class of debris as the orphaned channel
    /// directories `CaptureChannel.sweep` removes: a stored answer to a question
    /// nobody asks any more, sitting in shared state where the next person to
    /// grep for it will assume it means something.
    ///
    /// Removed on `load()` rather than on `resetToDefaults()`, because the whole
    /// point is that it happens on an ordinary launch of an existing install.
    ///
    /// `onDeviceAI` is the second of them and has the same shape. It backed a
    /// "Prefer on-device" switch in Settings › AI, and **nothing anywhere read
    /// it**: `RoutedIntelligence.route` tries the on-device model first whenever it
    /// says it can take the language, unconditionally, so the switch was already
    /// describing what the router does and could not change it. Removed rather than
    /// implemented — off would have meant "always prefer the cloud", which is a
    /// feature nobody asked for and which does nothing at all on the language this
    /// keyboard exists for, since Apple's model has no Hebrew either way.
    static let retiredKeys = ["screenContextCloudReplies", "onDeviceAI", "learnsFromTyping"]

    /// Takes the retired keys out of a store. Static and explicit about its
    /// argument so a test can drive it against a scratch suite; the singleton's
    /// own defaults are the App Group plist and are nobody's fixture.
    static func removeRetiredKeys(from defaults: UserDefaults) {
        for key in retiredKeys where defaults.object(forKey: key) != nil {
            defaults.removeObject(forKey: key)
            Self.log.notice("retired key removed \(key, privacy: .public)")
        }
    }

    // MARK: Onboarding

    @Published public var hasCompletedOnboarding: Bool = false {
        didSet { persist(hasCompletedOnboarding, forKey: Key.hasCompletedOnboarding) }
    }

    /// Whether the user has ever confirmed, in the app, that they switched to AI
    /// Keyboard with the globe key. The keyboard cannot tell the app it is
    /// running — `KeyboardPresence` is the closest honest signal — and this is
    /// the user-side confirmation that the handoff happened.
    @Published public var hasAcknowledgedKeyboardSwitch: Bool = false {
        didSet { persist(hasAcknowledgedKeyboardSwitch, forKey: Key.hasAcknowledgedKeyboardSwitch) }
    }

    // MARK: Look

    /// The accent both processes wear. Picked on the second onboarding step and
    /// changeable afterwards in Keys › Look.
    /// **Writes `Theme.palette` as well as the store, and the order matters.**
    /// `didSet` runs before `objectWillChange` reaches SwiftUI, so by the time a
    /// view rebuilds in response to this the global the colours read is already
    /// the new one. Setting it from the observing view instead — in an
    /// `onChange` — would render one frame in the old accent.
    @Published public var brandPalette: BrandPalette = .orange {
        didSet {
            persist(brandPalette.rawValue, forKey: Key.brandPalette)
            // Outside `persist`, deliberately: this half of the `didSet` is the
            // reason `load()` assigns this property unconditionally, and
            // suppressing it during a load would leave `Theme.palette` on the
            // shipped accent in a process that had just read the user's.
            Theme.palette = brandPalette
        }
    }

    /// The same choice, read out of the store at the moment it is needed.
    ///
    /// **The keyboard has to use this one, for the reason `storedAutocorrectLevel`
    /// exists.** The picker is in the app and every key it recolours is drawn in
    /// the keyboard extension; those are two processes, and `load()` fills the
    /// `@Published` copy above once, when whichever process asked was launched.
    /// iOS keeps a keyboard extension alive across host apps, so an instance
    /// that was already running when the user changed palette would otherwise go
    /// on drawing the old accent — which, for a setting whose entire visible
    /// effect is a colour, looks exactly like the setting not working.
    public var storedBrandPalette: BrandPalette {
        defaults.string(forKey: Key.brandPalette).flatMap(BrandPalette.init(rawValue:))
            ?? brandPalette
    }

    // MARK: Languages

    /// What a keyboard with no stored list draws — which, until Full Access is
    /// granted, is every keyboard, because iOS withholds the shared container
    /// until then. Named so the sentence that warns about that
    /// (`SetupState.languagesNeedFullAccess`) can be checked against it rather
    /// than against a remembered pair.
    public static let shippedDefaultLanguages: [KeyboardLanguage] = [.english, .hebrew]

    @Published public var enabledLanguages: [KeyboardLanguage] = SharedStore.shippedDefaultLanguages {
        didSet { persist(enabledLanguages.map(\.rawValue), forKey: Key.enabledLanguages) }
    }

    /// The language list as the keyboard must read it: from UserDefaults at the
    /// moment of use, not from the `@Published` copy `load()` filled at launch.
    /// Same trap as `storedAutocorrectLevel`. The space bar prints these codes, so a
    /// stale copy is a swipe that names a language the user turned off.
    public var storedEnabledLanguages: [KeyboardLanguage] {
        if let raw = defaults.array(forKey: Key.enabledLanguages) as? [String] {
            let parsed = raw.compactMap(KeyboardLanguage.init(rawValue:))
            if !parsed.isEmpty { return parsed }
        }
        return enabledLanguages.isEmpty ? Self.shippedDefaultLanguages : enabledLanguages
    }

    /// The language a freshly launched keyboard draws.
    ///
    /// **iOS builds a new `KeyboardViewController` far more often than a user
    /// changes their mind.** The extension is torn down when it is not needed and
    /// rebuilt on the next field, so before this every launch opened on
    /// `enabledLanguages.first` — English for the shipped pair — and a Hebrew
    /// speaker slid the space bar back by hand several times a day. The keys are
    /// the one piece of keyboard state a user sets deliberately and expects to
    /// find where they left it.
    ///
    /// **Validated against the enabled list rather than trusted**, so a language
    /// turned off in the app cannot come back on the next launch, and a rawValue
    /// from an older build that no longer names a language falls through. The
    /// fallback is exactly what this replaced.
    ///
    /// Deliberately *not* `storedDictationLanguage`, which also holds a
    /// `KeyboardLanguage.rawValue` written by the keyboard. That one records what
    /// the keys were showing at the moment a dictation utterance opened, for the
    /// app process to transcribe against; it is written only on that tap, so a
    /// user who never dictates would have nothing here and a user who dictated in
    /// English an hour ago would reopen in it.
    public var storedOpeningLanguage: KeyboardLanguage {
        let enabled = storedEnabledLanguages
        if let remembered = defaults.string(forKey: Key.lastLanguage)
            .flatMap(KeyboardLanguage.init(rawValue:)), enabled.contains(remembered)
        {
            return remembered
        }
        return enabled.first ?? .english
    }

    /// Records the language the user has just put the keyboard on.
    ///
    /// **Only a language the *user* chose.** `KeyboardController.stepLanguage` is
    /// the one caller, and it is where the globe key and a slide along the space
    /// bar both land. The keyboard's own imposition on an ASCII field
    /// (`adoptFieldKeyboardType`) deliberately does not come through here: it
    /// already puts the language back when the user leaves the field, and
    /// remembering it would carry one email address into every app on the phone
    /// and outlast the process that could undo it.
    ///
    /// One string write to `UserDefaults`, on an action a person takes a few
    /// times a minute at most. Nothing worth debouncing, the same judgement
    /// `recordDictationLanguage` makes.
    public func rememberLanguage(_ language: KeyboardLanguage) {
        defaults.set(language.rawValue, forKey: Key.lastLanguage)
    }

    /// Appends or removes `language` from `enabledLanguages`.
    ///
    /// Returns `false` without mutating if the toggle would leave the list empty
    /// (a keyboard with no language has nothing to draw). Feedback and animation
    /// are the caller's responsibility: `Feedback` imports UIKit and
    /// `withAnimation` imports SwiftUI, neither of which belongs in this store.
    @discardableResult
    public func toggleEnabledLanguage(_ language: KeyboardLanguage) -> Bool {
        if enabledLanguages.contains(language) {
            guard enabledLanguages.count > 1 else { return false }
            enabledLanguages.removeAll { $0 == language }
        } else {
            enabledLanguages.append(language)
        }
        return true
    }

    // MARK: Typing

    /// How much evidence the space bar needs before it replaces what was typed.
    /// `AutocorrectLevel.shippedDefault` carries the default and the measurement
    /// behind it.
    @Published public var autocorrectLevel: AutocorrectLevel = .shippedDefault {
        didSet { persist(autocorrectLevel.rawValue, forKey: Key.autocorrectLevel) }
    }

    /// Whether space may replace the typed word with the default suggestion, and
    /// on how much evidence.
    ///
    /// **The keyboard has to use this one, for the reason `storedPersonalDictionary`
    /// exists.** The setting lives in the app and the space bar lives in the
    /// keyboard extension; those are two processes, and `load()` fills the
    /// `@Published` copy above once, when whichever process asked was launched. A
    /// keyboard already on screen when the user turned autocorrect off would
    /// otherwise keep committing the correction — which looks exactly like the
    /// setting not working.
    ///
    /// **The old boolean is migrated through a separate key, and the reason is
    /// that reusing the old one would have looked like it worked.**
    /// `Key.autocorrect` held a `Bool`, and `UserDefaults` reads a stored `Bool`
    /// back as the integer 1 — which happens to be `.confident`. Landing on the
    /// right answer by coercion is not the same as deciding it, and it would have
    /// read `.full` back as an unset key on any build that still wrote a boolean.
    ///
    /// An upgrade lands where a fresh install lands: an install that had
    /// Autocorrect **on** gets `shippedDefault`, because "on" is one answer to a
    /// question that now has two, and the product's answer to it is the same for
    /// everybody. **Off stays off** — that one is not ambiguous, and somebody who
    /// switched autocorrect off does not want it back.
    public var storedAutocorrectLevel: AutocorrectLevel {
        if defaults.object(forKey: Key.autocorrectLevel) != nil {
            return AutocorrectLevel(rawValue: defaults.integer(forKey: Key.autocorrectLevel))
                ?? .shippedDefault
        }
        if defaults.object(forKey: Key.autocorrect) != nil {
            return defaults.bool(forKey: Key.autocorrect) ? .shippedDefault : .off
        }
        return autocorrectLevel
    }

    /// Finish the word after a pause. Off on a fresh install: it rewrites the
    /// field without a tap, and nobody should be opted into that. The wait is
    /// `idleDelayMs`, not a hardcoded 300.
    @Published public var completeOnIdle = false {
        didSet { persist(completeOnIdle, forKey: Key.completeOnIdle) }
    }

    /// Add a space after a 300 ms pause. Separate from completing the word, and
    /// off for the same reason: a space the user did not press is easy to hate.
    @Published public var spaceOnIdle = false {
        didSet { persist(spaceOnIdle, forKey: Key.spaceOnIdle) }
    }

    /// Same cross-process rule as `storedAutocorrectLevel`: the toggle is in the app
    /// and the pause lives in the keyboard extension.
    public var storedCompleteOnIdle: Bool {
        if defaults.object(forKey: Key.completeOnIdle) != nil {
            return defaults.bool(forKey: Key.completeOnIdle)
        }
        return completeOnIdle
    }

    public var storedSpaceOnIdle: Bool {
        if defaults.object(forKey: Key.spaceOnIdle) != nil {
            return defaults.bool(forKey: Key.spaceOnIdle)
        }
        return spaceOnIdle
    }

    /// How long to wait after the last keystroke before Complete on pause or
    /// Space on pause fire. 300 ms ships. The picker is 100 ms jumps from 200
    /// to 600: shorter than 200 catches the gap between keys, longer than 600
    /// is a wait you feel as the keyboard ignoring you.
    @Published public var idleDelayMs = 300 {
        didSet { persist(idleDelayMs, forKey: Key.idleDelayMs) }
    }

    public static let idleDelayChoices = Array(stride(from: 200, through: 600, by: 100))

    /// Same cross-process rule as `storedAutocorrectLevel`. An unknown stored value
    /// falls back to 300 rather than firing on the next keystroke.
    public var storedIdleDelayMs: Int {
        let stored: Int
        if defaults.object(forKey: Key.idleDelayMs) != nil {
            stored = defaults.integer(forKey: Key.idleDelayMs)
        } else {
            stored = idleDelayMs
        }
        return Self.idleDelayChoices.contains(stored) ? stored : 300
    }

    @Published public var autocapitalise = true {
        didSet { persist(autocapitalise, forKey: Key.autocapitalise) }
    }

    /// Same cross-process rule as `storedAutocorrectLevel`: the toggle is in the app
    /// and Return / double-space capitalise in the keyboard extension.
    public var storedAutocapitalise: Bool {
        if defaults.object(forKey: Key.autocapitalise) != nil {
            return defaults.bool(forKey: Key.autocapitalise)
        }
        return autocapitalise
    }

    @Published public var predictions = true { didSet { persist(predictions, forKey: Key.predictions) } }

    /// How many letters share one key. `.off` ships, and that is not timidity:
    /// `Bar/grouped/` measured the trade and the gentlest setting still costs
    /// about a point and a half of accuracy, which nobody should be opted into.
    @Published public var groupedLevel: GroupedKeys.Level = .off {
        didSet { persist(groupedLevel.rawValue, forKey: Key.groupedLevel) }
    }

    /// **Read at the keystroke, never from the `@Published` copy.** Exactly the
    /// `storedAutocorrectLevel` trap: the switch lives in the containing app and every
    /// press it governs happens in the extension, so an instance iOS kept alive
    /// would go on grouping keys after the user turned the feature off — and with
    /// grouping the mismatch is not a wrong suggestion, it is every keystroke
    /// typing the wrong letter.
    public var storedGroupedLevel: GroupedKeys.Level {
        guard defaults.object(forKey: Key.groupedLevel) != nil else { return groupedLevel }
        return GroupedKeys.Level(rawValue: defaults.integer(forKey: Key.groupedLevel)) ?? .off
    }

    /// Whether the suggestion bar is shown at all.
    ///
    /// Same cross-process rule as `storedAutocorrectLevel`: the toggle is in the app
    /// and the bar is drawn by the keyboard, so a read of the `@Published` copy
    /// alone keeps offering candidates after the user turned them off.
    public var storedPredictions: Bool {
        if defaults.object(forKey: Key.predictions) != nil {
            return defaults.bool(forKey: Key.predictions)
        }
        return predictions
    }

    @Published public var haptics = true { didSet { persist(haptics, forKey: Key.haptics) } }
    @Published public var keySounds = true { didSet { persist(keySounds, forKey: Key.keySounds) } }

    /// The two feedback switches, as `Feedback` reads them at the press.
    ///
    /// **Same rule as `storedAutocorrectLevel`, and this pair was the worse instance
    /// of it.** Both switches are in the app; every press they gate happens in
    /// the keyboard extension. `Feedback` used to hold plain `Bool`s filled once
    /// from `KeyboardViewController.viewDidLoad`, and the `didSet`s here used to
    /// push new values into them — which works in the app's own process and does
    /// nothing at all for an extension instance iOS is keeping alive. So a user
    /// who turned the sound off, came back to the same host app and got the same
    /// keyboard instance kept hearing it, which reads as the toggle not working.
    /// Going through `defaults` at the press cannot go stale.
    public var storedHaptics: Bool {
        if defaults.object(forKey: Key.haptics) != nil { return defaults.bool(forKey: Key.haptics) }
        return haptics
    }
    public var storedKeySounds: Bool {
        if defaults.object(forKey: Key.keySounds) != nil { return defaults.bool(forKey: Key.keySounds) }
        return keySounds
    }

    /// How hard a press hits when haptics are on at all.
    ///
    /// A second setting rather than a fourth stop on the switch, so an install
    /// that already has `haptics` off keeps it off with nothing to migrate, and
    /// so turning haptics back on returns the strength the user last chose.
    @Published public var hapticStrength: HapticStrength = .default {
        didSet { persist(hapticStrength.rawValue, forKey: Key.hapticStrength) }
    }

    /// Same cross-process rule as the pair above, and the same consequence: the
    /// dial is in the app, every press it shapes happens in the keyboard, so a
    /// read of the `@Published` copy keeps hitting at the old strength for as
    /// long as iOS holds that extension instance.
    public var storedHapticStrength: HapticStrength {
        guard defaults.object(forKey: Key.hapticStrength) != nil else { return hapticStrength }
        return HapticStrength(rawValue: defaults.integer(forKey: Key.hapticStrength)) ?? .default
    }

    // MARK: AI

    @Published public var defaultTone: ToneStyle = .normal {
        didSet { persist(defaultTone.rawValue, forKey: Key.defaultTone) }
    }

    // MARK: Dictation handoff

    /// The deep link the keyboard writes to the shared store and the app opens on
    /// launch. Stable so the keyboard can record it before the app is running.
    public static let dictationStartURL = URL(string: "aikeyboard://dictation/start")!

    /// Opens the containing app directly on its Settings tab.
    public static let settingsURL = URL(string: "aikeyboard://settings")!

    /// Opens the containing app on Home, where the user can tap Apple's
    /// Start Broadcast button. The keyboard cannot present that picker
    /// over itself.
    public static let screenContextURL = URL(string: "aikeyboard://screen-context")!

    /// Records a timestamped intent for the app to start a dictation session.
    ///
    /// Called by the keyboard before it asks the system to foreground the app.
    /// The timestamp lets the app discard stale requests — a handoff written
    /// during a previous session that somehow was not consumed.
    public func recordDictationHandoff() {
        recordDictationHandoff(at: Date())
    }

    /// Consumes a pending handoff request if one exists and is still fresh.
    ///
    /// Returns `true` exactly once per `recordDictationHandoff()` call, and only
    /// within 30 seconds of it. The key is removed on every call, so a stale
    /// request does not linger and a second call in the same app launch returns
    /// `false`. 30 seconds is generous for a warm foreground switch and short
    /// enough that a request from a previous session cannot trigger an
    /// auto-start hours later.
    ///
    /// Future timestamps (clock skew, tampered store) are also rejected: a
    /// negative age means the timestamp was written after now, which should not
    /// happen and must not trigger an auto-start.
    public func consumeDictationHandoff() -> Bool {
        consumeDictationHandoff(at: Date())
    }

    // MARK: Internal date seams (used by tests via @testable import)

    /// Records a handoff at the given date. The public overload uses `Date()`
    /// so shipping code never passes an explicit date.
    func recordDictationHandoff(at date: Date) {
        defaults.set(date.timeIntervalSince1970, forKey: Key.dictationHandoffRequest)
    }

    /// Consumes a handoff relative to the given date. The public overload uses
    /// `Date()`. Accepts the same freshness window as the public overload so
    /// tests can drive both sides of the 30-second boundary.
    func consumeDictationHandoff(at now: Date) -> Bool {
        guard let ts = defaults.object(forKey: Key.dictationHandoffRequest) as? Double else {
            return false
        }
        defaults.removeObject(forKey: Key.dictationHandoffRequest)
        let age = now.timeIntervalSince1970 - ts
        return age >= 0 && age < 30
    }

    // MARK: Dictation language

    /// The language the keyboard's layout was set to when it last opened a
    /// dictation utterance — not `enabledLanguages`, which is every language
    /// the user has ever turned on rather than the one they are dictating into
    /// right now. `nil` means the keyboard has never opened an utterance in
    /// this shared container: a session can be started and stopped from the
    /// app alone, with no keyboard involved at all, and this must not claim a
    /// language for that.
    ///
    /// **Read through `defaults` at the moment of use, on purpose, with no
    /// `@Published` copy to reach for instead.** This is the
    /// `storedPersonalDictionary` / `storedAutocorrectLevel` trap in the direction
    /// that setting has never run in: the keyboard extension writes it and
    /// `DictationService`, in the containing app, is a different process that
    /// may have been running since long before the write happened. A
    /// `@Published` copy would only ever be right in the process that just
    /// wrote it.
    public var storedDictationLanguage: KeyboardLanguage? {
        defaults.string(forKey: Key.dictationActiveLanguage).flatMap(KeyboardLanguage.init(rawValue:))
    }

    /// Records the language the keyboard is showing right now. Cheap enough to
    /// call on every utterance and on every language switch — one string write
    /// to `UserDefaults`, nothing worth debouncing.
    public func recordDictationLanguage(_ language: KeyboardLanguage) {
        defaults.set(language.rawValue, forKey: Key.dictationActiveLanguage)
    }

    // MARK: Personal dictionary

    /// The list a fresh install starts with.
    ///
    /// Named rather than left inline so `resetToDefaults()` can put it back — it
    /// removed the key and left the in-memory list alone, which is a reset that
    /// does not reset — and so `PersonalDictionaryTests` can hold *these* words to
    /// surviving the space bar. They are the ones the defect was measured on:
    /// every one of them was destroyed by this keyboard's own autocorrect.
    public static let shippedPersonalDictionary = [
        "Nitai", "Handi", "Wispr", "KeyboardKit", "סאפא", "בלי־פרופ"
    ]

    /// Names and words the keyboard must never correct. `DictionaryView` edits
    /// this; `SuggestionEngine` is what honours it, through
    /// `KeyboardController.refreshSuggestions`.
    @Published public var personalDictionary: [String] = SharedStore.shippedPersonalDictionary
    {
        didSet { persist(personalDictionary, forKey: Key.personalDictionary) }
    }

    /// The same list, read out of the store at the moment it is needed.
    ///
    /// **The keyboard has to use this one, for the reason `storedDefaultTone`
    /// exists.** The editor is in the app and the reader is in the keyboard
    /// extension; those are two processes, and `load()` fills the `@Published`
    /// copy above once, when whichever process asked was launched. A keyboard
    /// already on screen when a word was added would otherwise keep autocorrecting
    /// it away — which, since adding a word is the only thing the dictionary
    /// screen does, looks exactly like the feature not working.
    ///
    /// An empty stored array is honoured rather than treated as absent: a user who
    /// removed every word meant it. `load()` guarded on `!words.isEmpty` and so
    /// disagreed with this — a fresh app process re-seeded the published copy with
    /// the six shipped words while the keyboard was correctly honouring none, so
    /// Settings counted "6" that were not in effect and the next add wrote all six
    /// back into effect. Harmless while nothing read the list; not once something
    /// did.
    public var storedPersonalDictionary: [String] {
        defaults.array(forKey: Key.personalDictionary) as? [String] ?? personalDictionary
    }

    // MARK: Recent emoji

    /// What the Recent tab shows before the user has picked anything.
    public static let shippedRecentEmoji = ["😂", "🙏", "❤️", "👍", "🔥", "😅"]

    /// The emoji last inserted, most recent first.
    ///
    /// **Persisted, and it was not.** This lived in `KeyboardController` as a
    /// plain `@Published` array with nowhere to go, and iOS tears a keyboard
    /// extension down whenever it feels like it — every time the host app changed
    /// field, went to the background, or was simply not used for a while. So the
    /// Recent tab reset to the six shipped emoji constantly, which for a tab whose
    /// entire job is remembering is the feature not working at all.
    ///
    /// Written by the keyboard rather than by the app, the opposite direction to
    /// every other setting here. Without Full Access the container is
    /// process-local (see `SharedStore.storage`) and recents live only as long as
    /// the extension does — the same honest degradation the rest of the store has.
    @Published public var recentEmoji: [String] = SharedStore.shippedRecentEmoji {
        didSet { persist(recentEmoji, forKey: Key.recentEmoji) }
    }

    /// The same list, read at the moment it is needed, for the reason
    /// `storedPersonalDictionary` exists: the process that wrote it may not be the
    /// process reading it. An empty stored list is honoured — a user who cleared
    /// their recents meant it.
    public var storedRecentEmoji: [String] {
        defaults.array(forKey: Key.recentEmoji) as? [String] ?? recentEmoji
    }

    /// The skin tone the emoji grid draws itself in, picked by holding a cell.
    ///
    /// Written by the keyboard, the same direction as `recentEmoji` and for the
    /// same reason: the picker that sets it only exists there. Stored as the raw
    /// number so an older build reading a newer one sees an `Int` it can fall
    /// back from rather than a decode failure — see `EmojiSkinTone.stored(_:)`.
    @Published public var emojiSkinTone: EmojiSkinTone = .generic {
        didSet { persist(emojiSkinTone.rawValue, forKey: Key.emojiSkinTone) }
    }

    /// Read at the moment it is needed, because the process that wrote it is not
    /// the process reading it. `0` is both "never set" and "plain", which are the
    /// same picture, so an absent key needs no separate answer.
    public var storedEmojiSkinTone: EmojiSkinTone {
        EmojiSkinTone.stored(defaults.integer(forKey: Key.emojiSkinTone))
    }

    // MARK: CopyClip

    /// Copied texts plus the last pasteboard generation this keyboard saw.
    ///
    /// **JSON `CopyclipRecord`, not `[String]`, because swipe-delete needs a
    /// stable id and Clear must survive a killed extension.** A string list
    /// cannot tell two identical copies apart after a move-to-front. Leaving
    /// `lastChangeCount` in session memory would re-add the current board
    /// after Clear the next time iOS tore the keyboard down. The write is in
    /// `didSet` the way `recentEmoji` and the layout already are.
    @Published public var copyclipRecord: CopyclipRecord = .empty {
        didSet { if !isLoading { writeCopyclipRecord(copyclipRecord) } }
    }

    public static let copyclipHistoryKey = Key.copyclipHistory

    /// Re-read at the moment of use. An empty stored list is a list the user
    /// cleared, not a missing key.
    public var storedCopyclipRecord: CopyclipRecord {
        cachedCopyclipRecord().record
    }

    /// The stored record and whether reading it meant upgrading the older
    /// `[Clip]` shape, decoded at most once per distinct stored value. See
    /// `StoredDecode`.
    func cachedCopyclipRecord() -> (record: CopyclipRecord, migrated: Bool) {
        copyclipCache.value(for: defaults.data(forKey: Key.copyclipHistory)) {
            Self.decodedCopyclipRecord(from: defaults)
        }
    }

    static func decodeCopyclipRecord(from defaults: UserDefaults) -> CopyclipRecord {
        decodedCopyclipRecord(from: defaults).record
    }

    /// The same decode, plus whether the bytes were the pre-`CopyclipRecord`
    /// `[Clip]` array. Same shape and same single caller as
    /// `decodedLayout(from:)`: `persistMigrations()` is what keeps the upgrade in
    /// the plist now that a load does not write back what it read. Writing it
    /// once is what stops it being asked again, since the blob is then the new
    /// shape.
    static func decodedCopyclipRecord(
        from defaults: UserDefaults
    ) -> (
        record: CopyclipRecord, migrated: Bool
    ) {
        guard let data = defaults.data(forKey: Key.copyclipHistory) else { return (.empty, false) }
        if let record = try? JSONDecoder().decode(CopyclipRecord.self, from: data) {
            return (record, false)
        }
        if let clips = try? JSONDecoder().decode([Clip].self, from: data) {
            return (CopyclipRecord(clips: clips, lastChangeCount: -1), true)
        }
        // **A blob that exists and decodes as neither shape counts as a
        // migration**, which is the same answer `decodedLayout` gives for its
        // twin case and the opposite of what the first version of this said. The
        // unconditional write-back used to clear the corrupt bytes; reporting
        // `false` would leave them on disk forever and charge every future
        // `load()` two failed JSON decodes of them, which breaks the
        // self-limiting property `persistMigrations` requires of everything it
        // writes. Writing `.empty` over them is what stops it being asked again.
        return (.empty, true)
    }

    /// Encodes and writes, with no opinion about whether it should have been
    /// called. The `didSet` above holds the `isLoading` guard, for the reason
    /// `writeLayout` gives.
    func writeCopyclipRecord(_ record: CopyclipRecord) {
        guard let data = try? JSONEncoder().encode(record) else {
            Self.log.error("copyclip history could not be encoded, the change was not saved")
            return
        }
        defaults.set(data, forKey: Key.copyclipHistory)
    }

    // MARK: Keyboard layout

    /// The shape of the keyboard, as the editor in the app last left it.
    @Published public var keyboardLayout: KeyboardCustomization = .default {
        didSet { if !isLoading { writeLayout(keyboardLayout) } }
    }

    // MARK: Screen context

    /// Whether the user has opted into screen context in the app. Separate from
    /// whether a capture session is running, and weaker: Apple makes the user
    /// start the session through its own picker, so a live session is its own
    /// permission and this only gates the scripted in-app demo.
    ///
    /// There is deliberately no "keep screen reading on the device" switch beside
    /// it. In the ReplayKit capture flow the read is cloud-only — the accuracy
    /// argument is measured on iOS in `ScreenContextBarTests` — so a switch
    /// promising otherwise would be a promise no code keeps.
    @Published public var screenContextAllowed = false {
        didSet { persist(screenContextAllowed, forKey: Key.screenContextAllowed) }
    }

    // MARK: Billing

    @Published public var isSubscribed = false {
        didSet { persist(isSubscribed, forKey: Key.isSubscribed) }
    }

}
