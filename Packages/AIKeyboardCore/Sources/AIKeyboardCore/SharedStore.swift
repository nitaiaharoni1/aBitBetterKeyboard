import Foundation
import Combine

/// Settings the app writes and the keyboard reads.
///
/// The real product moves this behind an App Group so both processes see one
/// store. Until entitlements are wired up, each process keeps its own copy and
/// the keyboard falls back to sensible defaults — swapping in the shared suite
/// is a one-line change here and nowhere else.
public final class SharedStore: ObservableObject {

    public static let appGroupIdentifier = "group.com.nitai.aikeyboard"

    public static let shared = SharedStore()

    private let defaults: UserDefaults

    private init() {
        defaults = UserDefaults(suiteName: Self.appGroupIdentifier) ?? .standard
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
    @Published public var autocapitalise = true { didSet { defaults.set(autocapitalise, forKey: Key.autocapitalise) } }
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

    @Published public var preferOnDeviceAI = true { didSet { defaults.set(preferOnDeviceAI, forKey: Key.onDeviceAI) } }
    @Published public var defaultTone: ToneStyle = .clearer {
        didSet { defaults.set(defaultTone.rawValue, forKey: Key.defaultTone) }
    }

    // MARK: Personal dictionary

    @Published public var personalDictionary: [String] = [
        "Nitai", "Handi", "Wispr", "KeyboardKit", "סאפא", "בלי־פרופ"
    ] {
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

    @Published public var isSubscribed = false { didSet { defaults.set(isSubscribed, forKey: Key.isSubscribed) } }

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
        if defaults.object(forKey: Key.autocorrect) != nil { autocorrect = defaults.bool(forKey: Key.autocorrect) }
        if defaults.object(forKey: Key.autocapitalise) != nil { autocapitalise = defaults.bool(forKey: Key.autocapitalise) }
        if defaults.object(forKey: Key.predictions) != nil { predictions = defaults.bool(forKey: Key.predictions) }
        if defaults.object(forKey: Key.haptics) != nil { haptics = defaults.bool(forKey: Key.haptics) }
        if defaults.object(forKey: Key.keySounds) != nil { keySounds = defaults.bool(forKey: Key.keySounds) }
        if defaults.object(forKey: Key.onDeviceAI) != nil { preferOnDeviceAI = defaults.bool(forKey: Key.onDeviceAI) }
        if let tone = defaults.string(forKey: Key.defaultTone).flatMap(ToneStyle.init(rawValue:)) { defaultTone = tone }
        if let words = defaults.array(forKey: Key.personalDictionary) as? [String], !words.isEmpty {
            personalDictionary = words
        }
        if defaults.object(forKey: Key.isSubscribed) != nil { isSubscribed = defaults.bool(forKey: Key.isSubscribed) }
        if defaults.object(forKey: Key.screenContextAllowed) != nil {
            screenContextAllowed = defaults.bool(forKey: Key.screenContextAllowed)
        }
        if defaults.object(forKey: Key.screenContextCloud) != nil {
            screenContextCloudReplies = defaults.bool(forKey: Key.screenContextCloud)
        }
    }
}
