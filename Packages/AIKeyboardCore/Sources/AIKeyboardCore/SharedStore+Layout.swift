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
    /// **The globe is nobody's business here, and the validator no longer has an
    /// opinion about it either.** Whether the key is required is a property of the
    /// *device*, which the store cannot know; a layout missing it is repaired where
    /// that answer is known, in `KeyboardController.apply(_:)`. `replacingInternalGlobe`
    /// below is the other half of the same story: an older build stored `.globe`
    /// where the presets no longer place it, so a layout with no `.settings` at
    /// all is migrated rather than left holding that leftover key.
    public static func decodeLayout(from defaults: UserDefaults) -> KeyboardCustomization {
        guard let data = defaults.data(forKey: Key.keyboardLayout) else { return .default }
        guard let decoded = try? JSONDecoder().decode(KeyboardCustomization.self, from: data)
        else {
            log.error("stored keyboard layout could not be decoded, falling back to the default")
            return .default
        }
        // A named preset stores its identity, not a permanent snapshot of an old
        // build. Reload the current definition so fixes to shipped key widths
        // reach existing installs. Edited layouts clear `preset` and remain
        // untouched.
        if let preset = decoded.preset, let current = LayoutPreset.named(preset) {
            return current.customization
        }
        var migrated = decoded
        let slots =
            migrated.barLeading + migrated.barTrailing + migrated.bottomRow + migrated.cursorRow
        if !slots.contains(where: { $0.action == .settings }) {
            migrated.barLeading = replacingInternalGlobe(in: migrated.barLeading)
            migrated.barTrailing = replacingInternalGlobe(in: migrated.barTrailing)
            migrated.bottomRow = replacingInternalGlobe(in: migrated.bottomRow)
            migrated.cursorRow = replacingInternalGlobe(in: migrated.cursorRow)
        }
        guard LayoutValidator.isUsable(migrated) else {
            log.error("stored keyboard layout is not usable, falling back to the default")
            return .default
        }
        return migrated
    }

    private static func replacingInternalGlobe(in slots: [SlotSpec]) -> [SlotSpec] {
        slots.map { slot in
            guard slot.action == .globe else { return slot }
            var migrated = slot
            migrated.action = .settings
            return migrated
        }
    }

    func writeLayout(_ layout: KeyboardCustomization) {
        guard let data = try? JSONEncoder().encode(layout) else {
            Self.log.error("keyboard layout could not be encoded, the change was not saved")
            return
        }
        defaults.set(data, forKey: Key.keyboardLayout)
    }
}
