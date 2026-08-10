import Foundation
import Combine
import os

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

    private let defaults: UserDefaults

    /// The store the two processes actually share, for callers that need
    /// `UserDefaults` itself rather than one of the typed accessors below.
    ///
    /// Exposed because the alternative is worse: a caller reaching for
    /// `.standard` gets a store that works perfectly in the app, is private to
    /// the extension in the keyboard, and fails silently in exactly one of the
    /// two processes. `BackendTransport.configured` shipped that bug.
    public var userDefaults: UserDefaults { defaults }

    private static let log = Logger(subsystem: "com.nitai.aikeyboard", category: "SharedStore")

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
        static let autocorrect = "autocorrect"
        static let autocapitalise = "autocapitalise"
        static let predictions = "predictions"
        static let haptics = "haptics"
        static let keySounds = "keySounds"
        static let defaultTone = "defaultTone"
        /// The two `BackendTransport.configured` reads. It declares them inline in
        /// `AIKeyboardShared`, which cannot see this enum, so they are spelled
        /// twice on purpose and
        /// `BackendTransportSuiteTests.testConfiguredReadsWhicheverStoreItIsGiven`
        /// is what fails if the two spellings ever part.
        static let cloudBackendURL = "cloudBackendURL"
        static let cloudBackendToken = "cloudBackendToken"
        static let customToneInstruction = "customToneInstruction"
        static let prefersCustomTone = "prefersCustomTone"
        static let personalDictionary = "personalDictionary"
        static let isSubscribed = "isSubscribed"
        static let screenContextAllowed = "screenContextAllowed"
        static let dictationSessionMinutes = "dictationSessionMinutes"
        static let keyboardLayout = "keyboardLayout"
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
    static let retiredKeys = ["screenContextCloudReplies", "onDeviceAI"]

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
        didSet { defaults.set(hasCompletedOnboarding, forKey: Key.hasCompletedOnboarding) }
    }

    // MARK: Languages

    /// What a keyboard with no stored list draws — which, until Full Access is
    /// granted, is every keyboard, because iOS withholds the shared container
    /// until then. Named so the sentence that warns about that
    /// (`SetupState.languagesNeedFullAccess`) can be checked against it rather
    /// than against a remembered pair.
    public static let shippedDefaultLanguages: [KeyboardLanguage] = [.english, .hebrew]

    @Published public var enabledLanguages: [KeyboardLanguage] = SharedStore.shippedDefaultLanguages {
        didSet { defaults.set(enabledLanguages.map(\.rawValue), forKey: Key.enabledLanguages) }
    }

    // MARK: Typing

    @Published public var autocorrect = true { didSet { defaults.set(autocorrect, forKey: Key.autocorrect) } }
    @Published public var autocapitalise = true {
        didSet { defaults.set(autocapitalise, forKey: Key.autocapitalise) }
    }
    @Published public var predictions = true { didSet { defaults.set(predictions, forKey: Key.predictions) } }
    @Published public var haptics = true {
        didSet {
            defaults.set(haptics, forKey: Key.haptics)
            Task { @MainActor in Feedback.hapticsEnabled = haptics }
        }
    }
    @Published public var keySounds = true {
        didSet {
            defaults.set(keySounds, forKey: Key.keySounds)
            Task { @MainActor in Feedback.soundEnabled = keySounds }
        }
    }

    // MARK: AI

    @Published public var defaultTone: ToneStyle = .clearer {
        didSet { defaults.set(defaultTone.rawValue, forKey: Key.defaultTone) }
    }

    /// How long a dictation session stays open before it closes itself.
    ///
    /// **A session with no end is a microphone somebody forgot.** The recording
    /// runs in this app under the `audio` background mode, so it survives the
    /// switch to WhatsApp — which is the entire point, and is also exactly how a
    /// live microphone comes to be running an hour after the user last thought
    /// about it. Wispr Flow, which has the same architecture for the same
    /// reason, offers 5, 15, 60 and never; this offers the first three and no
    /// never, because "never" is the one choice that cannot be undone by
    /// forgetting.
    @Published public var dictationSessionMinutes = 15 {
        didSet { defaults.set(dictationSessionMinutes, forKey: Key.dictationSessionMinutes) }
    }

    public static let dictationSessionChoices = [5, 15, 60]

    // MARK: The cloud model

    /// The backend every cloud call goes to, exactly as typed.
    ///
    /// **One key, and it is the one the whole product turns on.** Three readers
    /// live off it — `KeyboardController`'s text actions, `ScreenReadService` in the
    /// capture process, and `ScreenContextSession` — and all three reach it through
    /// `BackendTransport.configured`. This is the writer, and until `CloudModelView`
    /// there was effectively only one, hidden on the Screen Context screen under a
    /// heading about screen reading, so a Hebrew rewrite failed forever with no way
    /// to find out why.
    ///
    /// Computed through `userDefaults` rather than `@Published`, exactly like
    /// `customTone`: the value is read by another process at the moment of a tap,
    /// and a published copy filled at launch would be the stale one. Empty removes
    /// the key rather than storing "", because `URL(string: "")` is a URL and a
    /// stored empty string would read back as a configured backend with no scheme.
    /// **Falls back to `BackendTransport.bundledDefaultURL` exactly as
    /// `BackendTransport.configured` does, and that agreement is the point.** This
    /// getter is what `CloudModelView` fills its field from, so a getter answering
    /// "" while the transport quietly used the built-in address would put an empty
    /// box and the words "Nothing set" in front of a user whose Hebrew rewrites
    /// were working. The screen has to describe the send that will actually happen.
    public var cloudBackendURL: String {
        get { BackendTransport.effectiveURL(defaults: defaults) }
        set { write(newValue, forKey: Key.cloudBackendURL) }
    }

    /// The optional bearer token sent beside it. See `BackendTransport.send` for
    /// what it is and is not, and `CloudModelView` for where it is stored.
    public var cloudBackendToken: String {
        get { defaults.string(forKey: Key.cloudBackendToken) ?? "" }
        set { write(newValue, forKey: Key.cloudBackendToken) }
    }

    /// Whether an AI action would find a cloud engine right now. The same question
    /// `BackendTransport.configured` answers, asked of this store so a screen can
    /// render it.
    public var hasCloudModel: Bool { BackendTransport.isReady(defaults: defaults) }

    private func write(_ value: String, forKey key: String) {
        objectWillChange.send()
        if value.isEmpty {
            defaults.removeObject(forKey: key)
        } else {
            defaults.set(value, forKey: key)
        }
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
        didSet { defaults.set(personalDictionary, forKey: Key.personalDictionary) }
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

    // MARK: Keyboard layout

    /// The key, exposed so `LayoutStoreTests` can write it into a scratch suite
    /// without reaching into a private enum.
    public static let layoutKey = Key.keyboardLayout

    /// The shape of the keyboard, as the editor in the app last left it.
    @Published public var keyboardLayout: KeyboardCustomization = .default {
        didSet { writeLayout(keyboardLayout) }
    }

    /// The same value, read out of the store at the moment it is needed.
    ///
    /// **The keyboard has to use this one, for the reason `storedDefaultTone` and
    /// `storedPersonalDictionary` exist.** The editor is in the app and the
    /// renderer is in the keyboard extension; those are two processes, and
    /// `load()` fills the `@Published` copy above once, when whichever process
    /// asked was launched. A keyboard already on screen when the user taps Done
    /// would otherwise keep drawing the shape they just changed, which looks
    /// exactly like the editor not working.
    public var storedKeyboardLayout: KeyboardCustomization {
        Self.decodeLayout(from: defaults)
    }

    /// **Falls back rather than throws, twice.** Unreadable JSON is a build that
    /// changed the model; a layout that fails the validator is a build that added
    /// a required key. Either one would otherwise be a keyboard that cannot draw
    /// itself, and that is not a state the user can get out of from inside the
    /// keyboard — they are in somebody else's app with no keys.
    ///
    /// `showsGlobe: false` here on purpose. Whether the globe is required is a
    /// property of the *device*, and the store does not know it. A layout missing
    /// the globe is repaired where that answer is known, in
    /// `KeyboardController.apply(_:)`.
    public static func decodeLayout(from defaults: UserDefaults) -> KeyboardCustomization {
        guard let data = defaults.data(forKey: Key.keyboardLayout) else { return .default }
        guard let decoded = try? JSONDecoder().decode(KeyboardCustomization.self, from: data)
        else {
            log.error("stored keyboard layout could not be decoded, falling back to the default")
            return .default
        }
        guard LayoutValidator.isUsable(decoded, showsGlobe: false) else {
            log.error("stored keyboard layout is not usable, falling back to the default")
            return .default
        }
        return decoded
    }

    private func writeLayout(_ layout: KeyboardCustomization) {
        guard let data = try? JSONEncoder().encode(layout) else {
            Self.log.error("keyboard layout could not be encoded, the change was not saved")
            return
        }
        defaults.set(data, forKey: Key.keyboardLayout)
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
        didSet { defaults.set(screenContextAllowed, forKey: Key.screenContextAllowed) }
    }

    // MARK: Billing

    @Published public var isSubscribed = false {
        didSet { defaults.set(isSubscribed, forKey: Key.isSubscribed) }
    }

    /// Puts every setting back to its shipped default. Used by the UI tests so a
    /// run never depends on what the previous run left behind.
    public func resetToDefaults() {
        for key in [
            Key.hasCompletedOnboarding, Key.enabledLanguages, Key.autocorrect,
            Key.autocapitalise, Key.predictions, Key.haptics, Key.keySounds,
            Key.defaultTone, Key.customToneInstruction, Key.dictationSessionMinutes,
            Key.prefersCustomTone, Key.personalDictionary,
            Key.isSubscribed, Key.screenContextAllowed, Key.keyboardLayout
            // Deliberately not `cloudBackendURL` or `cloudBackendToken`. A UI test
            // run would otherwise wipe the backend whoever is developing this
            // typed in, and it is the one setting here that cannot be recovered by
            // tapping a switch back on.
        ] {
            defaults.removeObject(forKey: key)
        }
        hasCompletedOnboarding = false
        enabledLanguages = Self.shippedDefaultLanguages
        autocorrect = true
        autocapitalise = true
        predictions = true
        haptics = true
        keySounds = true
        defaultTone = .clearer
        dictationSessionMinutes = 15
        personalDictionary = Self.shippedPersonalDictionary
        isSubscribed = false
        screenContextAllowed = false
        // Assigned as well as removed, for the reason `personalDictionary` is:
        // clearing the key and leaving the in-memory value alone is a reset that
        // does not reset, and the keyboard would keep drawing the old shape.
        keyboardLayout = .default
    }

    /// Loads persisted values without firing the `didSet` writes above.
    public func load() {
        Self.removeRetiredKeys(from: defaults)

        if defaults.object(forKey: Key.hasCompletedOnboarding) != nil {
            hasCompletedOnboarding = defaults.bool(forKey: Key.hasCompletedOnboarding)
        }
        if let raw = defaults.array(forKey: Key.enabledLanguages) as? [String] {
            let parsed = raw.compactMap(KeyboardLanguage.init(rawValue:))
            if !parsed.isEmpty { enabledLanguages = parsed }
        }
        if defaults.object(forKey: Key.autocorrect) != nil {
            autocorrect = defaults.bool(forKey: Key.autocorrect)
        }
        if defaults.object(forKey: Key.autocapitalise) != nil {
            autocapitalise = defaults.bool(forKey: Key.autocapitalise)
        }
        if defaults.object(forKey: Key.predictions) != nil {
            predictions = defaults.bool(forKey: Key.predictions)
        }
        if defaults.object(forKey: Key.haptics) != nil { haptics = defaults.bool(forKey: Key.haptics) }
        if defaults.object(forKey: Key.keySounds) != nil { keySounds = defaults.bool(forKey: Key.keySounds) }
        let minutes = defaults.integer(forKey: Key.dictationSessionMinutes)
        if Self.dictationSessionChoices.contains(minutes) { dictationSessionMinutes = minutes }
        if let tone = defaults.string(forKey: Key.defaultTone).flatMap(ToneStyle.init(rawValue:)) {
            defaultTone = tone
        }
        // No `!words.isEmpty` guard: an empty stored list is a list the user
        // emptied, and treating it as absent made this reader and
        // `storedPersonalDictionary` disagree about what is in force. Absent is
        // still the shipped default, because that is what the key not existing
        // means.
        if let words = defaults.array(forKey: Key.personalDictionary) as? [String] {
            personalDictionary = words
        }
        if defaults.object(forKey: Key.isSubscribed) != nil {
            isSubscribed = defaults.bool(forKey: Key.isSubscribed)
        }
        if defaults.object(forKey: Key.screenContextAllowed) != nil {
            screenContextAllowed = defaults.bool(forKey: Key.screenContextAllowed)
        }
        // Unguarded, because `decodeLayout` already answers `.default` for an
        // absent key and for anything it cannot use. A guard here would be a
        // second opinion about what "no stored layout" means, and the two would
        // eventually disagree.
        keyboardLayout = Self.decodeLayout(from: defaults)

        // The app and the keyboard are separate processes, and a process always
        // sees its own writes — so the only way to observe that the App Group is
        // genuinely shared is to watch both processes report what they read. The
        // unified log stamps each line with the process that emitted it, which
        // makes `AppGroupProof.sh` able to fail. Keep this in sync with the keys
        // that script greps for.
        Self.log.notice(
            """
            load storage=\(self.storage.rawValue, privacy: .public) \
            languages=\(self.enabledLanguages.map(\.rawValue).joined(separator: ","), privacy: .public) \
            onboarded=\(self.hasCompletedOnboarding, privacy: .public)
            """
        )
    }
}
