import Foundation

extension SharedStore {

    // MARK: Keyboard layout

    /// The key, exposed so `LayoutStoreTests` can write it into a scratch suite
    /// without reaching into a private enum.
    public static let layoutKey = Key.keyboardLayout

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

    func writeLayout(_ layout: KeyboardCustomization) {
        guard let data = try? JSONEncoder().encode(layout) else {
            Self.log.error("keyboard layout could not be encoded, the change was not saved")
            return
        }
        defaults.set(data, forKey: Key.keyboardLayout)
    }
}
