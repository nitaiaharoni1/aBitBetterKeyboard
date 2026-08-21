import Foundation

extension SharedStore {

    // MARK: Reset

    /// Puts every setting back to its shipped default. Used by the UI tests so a
    /// run never depends on what the previous run left behind.
    public func resetToDefaults() {
        for key in [
            Key.hasCompletedOnboarding, Key.enabledLanguages, Key.lastLanguage,
            // Both, and the legacy one is not optional here: `storedAutocorrectLevel`
            // reads it when the new key is absent, so a reset that cleared only the
            // new key would hand the next read the migrated value back.
            Key.autocorrect, Key.autocorrectLevel,
            Key.completeOnIdle, Key.spaceOnIdle, Key.idleDelayMs,
            Key.autocapitalise, Key.predictions, Key.haptics, Key.hapticStrength, Key.keySounds,
            Key.defaultTone, Key.customToneInstruction,
            Key.prefersCustomTone, Key.personalDictionary,
            Key.isSubscribed, Key.screenContextAllowed, Key.keyboardLayout,
            Key.recentEmoji, Key.emojiSkinTone, Key.copyclipHistory,
            Key.hasAcknowledgedKeyboardSwitch,
            Key.dictationHandoffRequest, Key.dictationActiveLanguage,
            Key.brandPalette
            // Deliberately not `cloudBackendURL` or `cloudBackendToken`. A UI test
            // run would otherwise wipe the backend whoever is developing this
            // typed in, and it is the one setting here that cannot be recovered by
            // tapping a switch back on.
            //
            // Nor the four the cloud connection is made of — `cloudSessionToken`,
            // `attestKeyId`, `attestationReport`, `attestationCheckedAt`. Those
            // are not settings at all: clearing them makes the next launch raise a
            // fresh attestation, and Apple rate-limits those per device, so a UI
            // suite that resets between cases would spend a real allowance per
            // test to arrive back where it started.
        ] {
            defaults.removeObject(forKey: key)
        }
        hasCompletedOnboarding = false
        hasAcknowledgedKeyboardSwitch = false
        brandPalette = .orange
        enabledLanguages = Self.shippedDefaultLanguages
        autocorrectLevel = .shippedDefault
        completeOnIdle = false
        spaceOnIdle = false
        idleDelayMs = 300
        autocapitalise = true
        predictions = true
        haptics = true
        hapticStrength = .default
        keySounds = true
        defaultTone = .normal
        personalDictionary = Self.shippedPersonalDictionary
        recentEmoji = Self.shippedRecentEmoji
        emojiSkinTone = .generic
        copyclipRecord = .empty
        isSubscribed = false
        screenContextAllowed = false
        // Assigned as well as removed, for the reason `personalDictionary` is:
        // clearing the key and leaving the in-memory value alone is a reset that
        // does not reset, and the keyboard would keep drawing the old shape.
        keyboardLayout = .default
    }

    // MARK: Migrations

    /// Writes back the three values `load()` read as something other than what
    /// was stored.
    ///
    /// **This is the exception `persist(_:forKey:)` exists to have.** A load that
    /// suppressed every write would be cheap and would silently stop three
    /// upgrades from sticking, which is the trap NIT-186 names and the reason
    /// this is a named function rather than a flag.
    ///
    /// **All three are self-limiting**, which is what makes them affordable:
    /// performing the write is exactly what stops the condition holding next
    /// time, so each costs one write per install and then nothing, for the life
    /// of that install. Anything added here has to have that property, or it
    /// puts a write back on every launch of every keyboard.
    ///
    /// These go through `defaults` and the two writers directly rather than
    /// through `persist(_:forKey:)`, because the whole point of them is to write
    /// while `isLoading` is still set.
    private func persistMigrations(layoutMigrated: Bool, copyclipMigrated: Bool) {
        // The pre-three-way boolean, upgraded by `storedAutocorrectLevel`. Also
        // catches a fresh install, where neither key exists and the accessor
        // hands back the shipped default — which is what the unconditional
        // write-back did, so keeping it here keeps the stored plist identical to
        // what every previous build produced.
        if defaults.object(forKey: Key.autocorrectLevel) == nil {
            defaults.set(autocorrectLevel.rawValue, forKey: Key.autocorrectLevel)
        }
        // The pre-`CopyclipRecord` `[Clip]` array.
        if copyclipMigrated { writeCopyclipRecord(copyclipRecord) }
        // The `.globe` → `.settings` repair, or a stored blob that exists and
        // cannot be used. A refreshed preset is deliberately not either of those
        // — see `decodedLayout(from:)`.
        if layoutMigrated { writeLayout(keyboardLayout) }
    }

    // MARK: Load

    /// Loads persisted values without firing the `didSet` writes above.
    ///
    /// **That sentence was false for the whole of this function's life, and is
    /// now true.** `didSet` fires on every assignment outside `init`, so each
    /// load wrote back all twenty-two values it had just read — two of them full
    /// JSON encodes re-serialising the layout and the copyclip record a line
    /// after deserialising them — and the keyboard runs this twice on a cold
    /// launch, in `viewDidLoad` and again in `viewWillAppear`, both before the
    /// first frame. `isLoading` and `persist(_:forKey:)` are what make the
    /// comment describe the code.
    ///
    /// The suppression is **not** wholesale, because three of the assignments
    /// below are migrations and for those the write-back is the thing that makes
    /// the migration stick. They are written explicitly by
    /// `persistMigrations(...)`, outside the window, and each one is
    /// self-limiting: writing it is what stops it being asked for again.
    public func load() {
        isLoading = true
        defer { isLoading = false }
        Self.removeRetiredKeys(from: defaults)

        if defaults.object(forKey: Key.hasCompletedOnboarding) != nil {
            hasCompletedOnboarding = defaults.bool(forKey: Key.hasCompletedOnboarding)
        }
        if defaults.object(forKey: Key.hasAcknowledgedKeyboardSwitch) != nil {
            hasAcknowledgedKeyboardSwitch = defaults.bool(forKey: Key.hasAcknowledgedKeyboardSwitch)
        }
        // Assigned unconditionally rather than only when the key exists, because
        // this is also what puts the shipped default into `Theme.palette` — the
        // published property starts on `.orange` and so would never fire its
        // `didSet` on a fresh install.
        brandPalette =
            defaults.string(forKey: Key.brandPalette).flatMap(BrandPalette.init(rawValue:))
            ?? .orange
        if let raw = defaults.array(forKey: Key.enabledLanguages) as? [String] {
            let parsed = raw.compactMap(KeyboardLanguage.init(rawValue:))
            if !parsed.isEmpty { enabledLanguages = parsed }
        }
        // Through the accessor rather than off the key, so the upgrade from the
        // old boolean happens in exactly one place. See `storedAutocorrectLevel`.
        autocorrectLevel = storedAutocorrectLevel
        if defaults.object(forKey: Key.completeOnIdle) != nil {
            completeOnIdle = defaults.bool(forKey: Key.completeOnIdle)
        }
        if defaults.object(forKey: Key.spaceOnIdle) != nil {
            spaceOnIdle = defaults.bool(forKey: Key.spaceOnIdle)
        }
        let delay = defaults.integer(forKey: Key.idleDelayMs)
        if Self.idleDelayChoices.contains(delay) { idleDelayMs = delay }
        if defaults.object(forKey: Key.autocapitalise) != nil {
            autocapitalise = defaults.bool(forKey: Key.autocapitalise)
        }
        if defaults.object(forKey: Key.predictions) != nil {
            predictions = defaults.bool(forKey: Key.predictions)
        }
        if let level = GroupedKeys.Level(rawValue: defaults.integer(forKey: Key.groupedLevel)) {
            groupedLevel = level
        }
        if defaults.object(forKey: Key.haptics) != nil { haptics = defaults.bool(forKey: Key.haptics) }
        if let strength = HapticStrength(rawValue: defaults.integer(forKey: Key.hapticStrength)) {
            hapticStrength = strength
        }
        if defaults.object(forKey: Key.keySounds) != nil { keySounds = defaults.bool(forKey: Key.keySounds) }
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
        emojiSkinTone = storedEmojiSkinTone
        // Absent key and unreadable JSON both stay empty. An empty stored
        // record is a user who tapped Clear, and must not be treated as missing.
        var copyclipMigrated = false
        if defaults.data(forKey: Key.copyclipHistory) != nil {
            let decoded = cachedCopyclipRecord()
            copyclipRecord = decoded.record
            copyclipMigrated = decoded.migrated
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
        let layout = cachedLayout()
        keyboardLayout = layout.layout

        persistMigrations(layoutMigrated: layout.migrated, copyclipMigrated: copyclipMigrated)

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
            onboarded=\(self.hasCompletedOnboarding, privacy: .public) \
            palette=\(self.brandPalette.rawValue, privacy: .public)
            """
        )
    }
}
