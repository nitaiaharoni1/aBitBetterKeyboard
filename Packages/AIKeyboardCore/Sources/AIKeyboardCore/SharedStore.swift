import Foundation
import Combine
import os

/// Settings the app writes and the keyboard reads.
///
/// Both targets carry the App Group entitlement, so `UserDefaults(suiteName:)`
/// resolves to one plist inside the shared container and a change made in the
/// app is visible to the keyboard extension.
public final class SharedStore: ObservableObject {

    public static let appGroupIdentifier = "group.com.nitai.aikeyboard"

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
        let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupIdentifier)

        if container != nil, let suite = UserDefaults(suiteName: Self.appGroupIdentifier) {
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

    private enum Key {
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let enabledLanguages = "enabledLanguages"
        static let autocorrect = "autocorrect"
        static let autocapitalise = "autocapitalise"
        static let predictions = "predictions"
        static let haptics = "haptics"
        static let keySounds = "keySounds"
        static let onDeviceAI = "onDeviceAI"
        static let defaultTone = "defaultTone"
        static let personalDictionary = "personalDictionary"
        static let isSubscribed = "isSubscribed"
        static let screenContextAllowed = "screenContextAllowed"
        static let screenContextCloud = "screenContextCloudReplies"
    }

    // MARK: Onboarding

    @Published public var hasCompletedOnboarding: Bool = false {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Key.hasCompletedOnboarding) }
    }

    // MARK: Languages

    @Published public var enabledLanguages: [KeyboardLanguage] = [.english, .hebrew] {
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

    @Published public var preferOnDeviceAI = true {
        didSet { defaults.set(preferOnDeviceAI, forKey: Key.onDeviceAI) }
    }
    @Published public var defaultTone: ToneStyle = .clearer {
        didSet { defaults.set(defaultTone.rawValue, forKey: Key.defaultTone) }
    }

    // MARK: Personal dictionary

    @Published public var personalDictionary: [String] = [
        "Nitai", "Handi", "Wispr", "KeyboardKit", "סאפא", "בלי־פרופ"
    ]
    {
        didSet { defaults.set(personalDictionary, forKey: Key.personalDictionary) }
    }

    // MARK: Screen context

    /// Whether the user wants Reply offered at all. Separate from whether a
    /// capture session is actually running: Apple makes the user start the
    /// session through its own picker, so this is a preference, not a permission.
    @Published public var screenContextAllowed = false {
        didSet { defaults.set(screenContextAllowed, forKey: Key.screenContextAllowed) }
    }

    /// Only the text read off the frame ever leaves the device. Turning this off
    /// keeps everything on-device and disables the cloud reply model.
    @Published public var screenContextCloudReplies = true {
        didSet { defaults.set(screenContextCloudReplies, forKey: Key.screenContextCloud) }
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
            Key.onDeviceAI, Key.defaultTone, Key.personalDictionary,
            Key.isSubscribed, Key.screenContextAllowed, Key.screenContextCloud
        ] {
            defaults.removeObject(forKey: key)
        }
        hasCompletedOnboarding = false
        enabledLanguages = [.english, .hebrew]
        autocorrect = true
        autocapitalise = true
        predictions = true
        haptics = true
        keySounds = true
        preferOnDeviceAI = true
        defaultTone = .clearer
        isSubscribed = false
        screenContextAllowed = false
        screenContextCloudReplies = true
    }

    /// Loads persisted values without firing the `didSet` writes above.
    public func load() {
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
        if defaults.object(forKey: Key.onDeviceAI) != nil {
            preferOnDeviceAI = defaults.bool(forKey: Key.onDeviceAI)
        }
        if let tone = defaults.string(forKey: Key.defaultTone).flatMap(ToneStyle.init(rawValue:)) {
            defaultTone = tone
        }
        if let words = defaults.array(forKey: Key.personalDictionary) as? [String], !words.isEmpty {
            personalDictionary = words
        }
        if defaults.object(forKey: Key.isSubscribed) != nil {
            isSubscribed = defaults.bool(forKey: Key.isSubscribed)
        }
        if defaults.object(forKey: Key.screenContextAllowed) != nil {
            screenContextAllowed = defaults.bool(forKey: Key.screenContextAllowed)
        }
        if defaults.object(forKey: Key.screenContextCloud) != nil {
            screenContextCloudReplies = defaults.bool(forKey: Key.screenContextCloud)
        }

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
