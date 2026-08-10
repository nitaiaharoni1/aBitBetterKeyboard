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

    let defaults: UserDefaults

    /// The store the two processes actually share, for callers that need
    /// `UserDefaults` itself rather than one of the typed accessors below.
    ///
    /// Exposed because the alternative is worse: a caller reaching for
    /// `.standard` gets a store that works perfectly in the app, is private to
    /// the extension in the keyboard, and fails silently in exactly one of the
    /// two processes. `BackendTransport.configured` shipped that bug.
    public var userDefaults: UserDefaults { defaults }

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
        static let cloudSessionToken = "cloudSessionToken"
        static let customToneInstruction = "customToneInstruction"
        static let prefersCustomTone = "prefersCustomTone"
        static let personalDictionary = "personalDictionary"
        static let isSubscribed = "isSubscribed"
        static let screenContextAllowed = "screenContextAllowed"
        static let dictationSessionMinutes = "dictationSessionMinutes"
        static let keyboardLayout = "keyboardLayout"
        static let recentEmoji = "recentEmoji"
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
        didSet { defaults.set(recentEmoji, forKey: Key.recentEmoji) }
    }

    /// The same list, read at the moment it is needed, for the reason
    /// `storedPersonalDictionary` exists: the process that wrote it may not be the
    /// process reading it. An empty stored list is honoured — a user who cleared
    /// their recents meant it.
    public var storedRecentEmoji: [String] {
        defaults.array(forKey: Key.recentEmoji) as? [String] ?? recentEmoji
    }

    // MARK: Keyboard layout

    /// The shape of the keyboard, as the editor in the app last left it.
    @Published public var keyboardLayout: KeyboardCustomization = .default {
        didSet { writeLayout(keyboardLayout) }
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

}
