import XCTest

@testable import AIKeyboardCore

/// Snapshot/restore for the `SharedStore` settings that space-bar tests write.
/// `SharedStore.init` is private and the singleton is the App Group plist, so
/// there is no scratch instance to build. Every test that writes a setting puts
/// it back.
///
/// Shared by `SpaceBarLanguageSwitchTests`, `SpaceBarGestureOrderTests` and
/// `LanguageMemoryTests`.
struct TypingSettings {
    let languages: [KeyboardLanguage]
    let autocorrect: Bool
    let predictions: Bool
    /// The remembered language as it is actually stored, so a run that had none
    /// gets none back. Restoring `storedOpeningLanguage` instead would write the
    /// fallback into the plist of every developer who ran the suite.
    let lastLanguage: String?

    static func snapshot() -> TypingSettings {
        let store = SharedStore.shared
        return TypingSettings(
            languages: store.enabledLanguages,
            autocorrect: store.autocorrect,
            predictions: store.predictions,
            lastLanguage: store.userDefaults.string(forKey: SharedStore.Key.lastLanguage))
    }

    func restore() {
        let store = SharedStore.shared
        store.enabledLanguages = languages
        store.autocorrect = autocorrect
        store.predictions = predictions
        if let lastLanguage {
            store.userDefaults.set(lastLanguage, forKey: SharedStore.Key.lastLanguage)
        } else {
            store.userDefaults.removeObject(forKey: SharedStore.Key.lastLanguage)
        }
    }
}
