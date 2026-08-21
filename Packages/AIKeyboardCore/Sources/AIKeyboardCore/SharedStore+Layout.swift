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
        cachedLayout().layout
    }

    /// The stored layout and whether reading it meant rewriting what an older
    /// build stored, decoded at most once per distinct stored value.
    ///
    /// **The freshness this accessor's doc comment promises is untouched**: the
    /// bytes are still read out of `UserDefaults` on every call, so a layout the
    /// editor saved in the app is a different `Data` and a real decode. What
    /// stops is decoding the *same* bytes five times before the keyboard's first
    /// frame. See `StoredDecode`.
    func cachedLayout() -> (layout: KeyboardCustomization, migrated: Bool) {
        layoutCache.value(for: defaults.data(forKey: Key.keyboardLayout)) {
            Self.decodedLayout(from: defaults)
        }
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
        decodedLayout(from: defaults).layout
    }

    /// The same decode, plus whether producing that answer meant rewriting what
    /// an older build stored.
    ///
    /// The flag has exactly one caller — `SharedStore.persistMigrations()` — and
    /// it exists because `load()` no longer writes back everything it reads. See
    /// `SharedStore.persist(_:forKey:)`.
    ///
    /// **Two things count and one deliberately does not.** The globe repair
    /// counts, and so does falling back over a blob that *exists* and cannot be
    /// used, because both of those replace a stored value with a different one
    /// and both stop being true once written — they cost one write per install
    /// and then never fire again. A refreshed **preset** does not count, and
    /// that is the case almost every install is in: reloading the named
    /// definition is how fixes to shipped key widths reach existing installs, so
    /// it is re-derived on every read by design and persisting it stores nothing
    /// that is not recomputed a moment later. Counting it would put a full JSON
    /// encode of the layout back on every `load()`, for everybody, forever —
    /// which is the cost this whole change is removing.
    static func decodedLayout(
        from defaults: UserDefaults
    ) -> (
        layout: KeyboardCustomization, migrated: Bool
    ) {
        guard let data = defaults.data(forKey: Key.keyboardLayout) else {
            return (.default, false)
        }
        guard let decoded = try? JSONDecoder().decode(KeyboardCustomization.self, from: data)
        else {
            log.error("stored keyboard layout could not be decoded, falling back to the default")
            return (.default, true)
        }
        // A named preset stores its identity, not a permanent snapshot of an old
        // build. Reload the current definition so fixes to shipped key widths
        // reach existing installs. Edited layouts clear `preset` and remain
        // untouched.
        if let preset = decoded.preset, let current = LayoutPreset.named(preset) {
            return (current.customization, false)
        }
        var migrated = decoded
        var replacedGlobe = false
        let slots =
            migrated.barLeading + migrated.barTrailing + migrated.bottomRow + migrated.cursorRow
        if !slots.contains(where: { $0.action == .settings }) {
            migrated.barLeading = replacingInternalGlobe(in: migrated.barLeading)
            migrated.barTrailing = replacingInternalGlobe(in: migrated.barTrailing)
            migrated.bottomRow = replacingInternalGlobe(in: migrated.bottomRow)
            migrated.cursorRow = replacingInternalGlobe(in: migrated.cursorRow)
            // The condition above, not the branch: a layout with no `.settings`
            // key and no `.globe` key either passes through here unchanged, and
            // saying it migrated would ask for a write that changes nothing and
            // does not stop the next load asking again.
            replacedGlobe = migrated != decoded
        }
        guard LayoutValidator.isUsable(migrated) else {
            log.error("stored keyboard layout is not usable, falling back to the default")
            return (.default, true)
        }
        return (migrated, replacedGlobe)
    }

    private static func replacingInternalGlobe(in slots: [SlotSpec]) -> [SlotSpec] {
        slots.map { slot in
            guard slot.action == .globe else { return slot }
            var migrated = slot
            migrated.action = .settings
            return migrated
        }
    }

    /// Encodes and writes, with no opinion about whether it should have been
    /// called. The `didSet` above holds the `isLoading` guard, so that a load
    /// skips the encode as well as the write, and so that
    /// `persistMigrations(...)` can still reach this. See
    /// `SharedStore.persist(_:forKey:)`.
    func writeLayout(_ layout: KeyboardCustomization) {
        guard let data = try? JSONEncoder().encode(layout) else {
            Self.log.error("keyboard layout could not be encoded, the change was not saved")
            return
        }
        defaults.set(data, forKey: Key.keyboardLayout)
    }
}
