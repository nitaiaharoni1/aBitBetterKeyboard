import XCTest

@testable import AIKeyboardCore

/// Snapshot/restore for the three `SharedStore` settings that space-bar tests
/// write. `SharedStore.init` is private and the singleton is the App Group plist,
/// so there is no scratch instance to build. Every test that writes a setting
/// puts it back.
///
/// Shared by `SpaceBarLanguageSwitchTests` and `SpaceBarGestureOrderTests`.
struct TypingSettings {
    let languages: [KeyboardLanguage]
    let autocorrect: Bool
    let predictions: Bool

    static func snapshot() -> TypingSettings {
        let store = SharedStore.shared
        return TypingSettings(
            languages: store.enabledLanguages,
            autocorrect: store.autocorrect,
            predictions: store.predictions)
    }

    func restore() {
        let store = SharedStore.shared
        store.enabledLanguages = languages
        store.autocorrect = autocorrect
        store.predictions = predictions
    }
}
