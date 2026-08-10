import Foundation

extension SharedStore {

    // MARK: Reset

    /// Puts every setting back to its shipped default. Used by the UI tests so a
    /// run never depends on what the previous run left behind.
    public func resetToDefaults() {
        for key in [
            Key.hasCompletedOnboarding, Key.enabledLanguages, Key.autocorrect,
            Key.autocapitalise, Key.predictions, Key.haptics, Key.keySounds,
            Key.defaultTone, Key.customToneInstruction, Key.dictationSessionMinutes,
            Key.prefersCustomTone, Key.personalDictionary,
            Key.isSubscribed, Key.screenContextAllowed, Key.keyboardLayout,
            Key.recentEmoji
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
        recentEmoji = Self.shippedRecentEmoji
        isSubscribed = false
        screenContextAllowed = false
        // Assigned as well as removed, for the reason `personalDictionary` is:
        // clearing the key and leaving the in-memory value alone is a reset that
        // does not reset, and the keyboard would keep drawing the old shape.
        keyboardLayout = .default
    }

    // MARK: Load

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
        // Same rule, same reason: a user who cleared their recents is not a user
        // who has none stored, and re-seeding the six shipped ones over an empty
        // list is exactly the reset this key was added to stop.
        if let emoji = defaults.array(forKey: Key.recentEmoji) as? [String] {
            recentEmoji = emoji
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
