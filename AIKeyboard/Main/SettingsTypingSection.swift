import AIKeyboardCore
import SwiftUI

/// The "Typing" settings card: autocorrect, pause actions, auto-capitalise,
/// predictions, number row, and keyboard layout.
struct SettingsTypingSection: View {
    @EnvironmentObject private var store: SharedStore

    /// Read once when the card appears rather than every redraw: the count walks
    /// the whole store, and nothing else on this screen can change it.
    @State private var learnedWordCount = 0

    /// Says what is kept, not that something is. A row promising the keyboard
    /// "learns" without saying what it writes down is the kind of setting people
    /// switch off on principle, and the honest answer is short enough to fit.
    private let learningSubtitle =
        "Remembers words and word pairs you type, on this device only. Never in password fields."

    /// Wider keys, several letters each, and the keyboard works out the word.
    ///
    /// **The accuracy is on the row, next to the choice, because it is the whole
    /// trade.** Every step up this dial makes the keys bigger and the guessing
    /// worse, and a picker that only says "Three letters" hides the half that
    /// costs something. The numbers are the top-1 rates measured in
    /// `Bar/grouped/results.json` — what the space bar would insert — and they are
    /// labelled as measured rather than promised.
    @ViewBuilder private var groupedKeysRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: Theme.Space.sm) {
                IconBadge(systemName: "rectangle.grid.1x2")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Grouped keys")
                        .font(Theme.Fonts.body)
                        .foregroundStyle(Theme.Text.primary)
                    Text("Bigger keys holding several letters. The keyboard picks the word.")
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Text.secondary)
                }
                Spacer(minLength: 0)
                Picker("Grouped keys", selection: $store.groupedLevel) {
                    ForEach(GroupedKeys.Level.allCases, id: \.self) { level in
                        Text(level.title).tag(level)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
            if store.groupedLevel != .off {
                let measured = store.groupedLevel.measuredAccuracy
                let hebrewCapped = store.groupedLevel.rawValue > GroupedKeys.Level.hebrewCeiling.rawValue
                Text(
                    hebrewCapped
                        ? "Measured: English \(measured.english)%. Hebrew stays at three letters "
                            + "(\(GroupedKeys.Level.hebrewCeiling.measuredAccuracy.hebrew)%), because four "
                            + "commits the wrong word about three times in ten. Tap a corner to pick "
                            + "that letter. Hold a key to pick one letter exactly."
                        : "Measured: the right word is chosen \(measured.english)% of the time in English, "
                            + "\(measured.hebrew)% in Hebrew. Tap a corner to pick that letter. "
                            + "Hold a key to pick one letter exactly."
                )
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Text.secondary)
                if !GroupedKeys.hasBundledLexicon(for: .english)
                    || !GroupedKeys.hasBundledLexicon(for: .hebrew)
                {
                    Text(
                        "This build has no full word list, so grouping only knows a few hundred common words."
                    )
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Text.secondary)
                }
            }
        }
    }

    /// How long to wait after the last key. Only drawn when a pause action is
    /// on, so the card does not ask about a wait nobody will feel.
    @ViewBuilder private var idleDelayRow: some View {
        HStack(spacing: Theme.Space.sm) {
            IconBadge(systemName: "timer")
            VStack(alignment: .leading, spacing: 2) {
                Text("Pause length")
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.Text.primary)
                Text("How long to wait after you stop typing")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.Text.secondary)
            }
            Spacer(minLength: 0)
            Picker("Pause length", selection: $store.idleDelayMs) {
                ForEach(SharedStore.idleDelayChoices, id: \.self) { ms in
                    Text("\(ms) ms").tag(ms)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            SectionHeader(title: "Typing")
            Card {
                VStack(spacing: Theme.Space.sm) {
                    ToggleRow(
                        title: "Autocorrect",
                        subtitle: "Space inserts the bold word. Turn off to keep what you typed.",
                        icon: "text.badge.checkmark",
                        isOn: $store.autocorrect
                    )
                    .searchTarget(.autocorrect)
                    Divider.themed
                    ToggleRow(
                        title: "Complete on pause",
                        subtitle: "Finishes the word you started after you stop typing for a moment",
                        icon: "text.cursor",
                        isOn: $store.completeOnIdle
                    )
                    .searchTarget(.completeOnPause)
                    Divider.themed
                    ToggleRow(
                        title: "Space on pause",
                        subtitle: "Adds a space after you stop typing for a moment",
                        icon: "space",
                        isOn: $store.spaceOnIdle
                    )
                    .searchTarget(.spaceOnPause)
                    if store.completeOnIdle || store.spaceOnIdle {
                        Divider.themed
                        idleDelayRow
                            .searchTarget(.pauseLength)
                    }
                    Divider.themed
                    ToggleRow(
                        title: "Auto-capitalise",
                        icon: "textformat",
                        isOn: $store.autocapitalise
                    )
                    .searchTarget(.autocapitalise)
                    Divider.themed
                    ToggleRow(
                        title: "Predictions",
                        subtitle: "Show the suggestion bar above the keys",
                        icon: "lightbulb",
                        isOn: $store.predictions
                    )
                    .searchTarget(.predictions)
                    Divider.themed
                    ToggleRow(
                        title: "Learn as you type",
                        subtitle: learningSubtitle,
                        icon: "brain",
                        isOn: $store.learnsFromTyping
                    )
                    .searchTarget(.learnAsYouType)
                    if learnedWordCount > 0 {
                        Divider.themed
                        // Only shown once there is something to clear. A row that
                        // always reads "0 words" invites the user to press it to
                        // find out what it does, and this is the one press here
                        // that cannot be undone.
                        Button(role: .destructive) {
                            PersonalLanguageModel.shared.clear()
                            learnedWordCount = 0
                        } label: {
                            HStack(spacing: Theme.Space.sm) {
                                IconBadge(systemName: "trash", tint: Theme.Semantic.record)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Forget what it learned")
                                    Text("\(learnedWordCount) words remembered on this device")
                                        .font(Theme.Fonts.caption)
                                        .foregroundStyle(Theme.Text.secondary)
                                }
                                Spacer(minLength: 0)
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.Semantic.record)
                    }
                    Divider.themed
                    groupedKeysRow
                        .searchTarget(.groupedKeys)
                    Divider.themed
                    ToggleRow(
                        title: "Number row",
                        subtitle: "Digits above the letters. Makes the keyboard taller.",
                        icon: "textformat.123",
                        isOn: numberRowBinding
                    )
                    .searchTarget(.numberRow)
                    Divider.themed
                    NavigationRow(
                        title: "Keyboard layout",
                        subtitle: "Presets, key size, and what each key does",
                        icon: "square.grid.3x2",
                        badge: layoutSummary
                    ) {
                        // Deliberately parameterless. Passing `store.keyboardLayout` here
                        // makes the pushed editor a function of the store, so tapping its
                        // Done button rebuilds it while it dismisses itself. See
                        // `LayoutView.init`.
                        LayoutView()
                    }
                }
            }
        }
        .onAppear { learnedWordCount = PersonalLanguageModel.shared.learnedWordCount }
    }

    /// Writes `showsNumberRow` and, if that moves the layout away from its
    /// preset, clears the preset too — the same thing `LayoutEditorModel.draft`'s
    /// `didSet` does for every edit made inside the layout editor itself.
    private var numberRowBinding: Binding<Bool> {
        Binding(
            get: { store.keyboardLayout.showsNumberRow },
            set: { newValue in
                store.keyboardLayout.showsNumberRow = newValue
                if let preset = store.keyboardLayout.preset,
                    LayoutPreset.named(preset)?.customization != store.keyboardLayout
                {
                    store.keyboardLayout.preset = nil
                }
            }
        )
    }

    /// The preset's name, or that it has been edited away from one.
    private var layoutSummary: String {
        guard let id = store.keyboardLayout.preset, let preset = LayoutPreset.named(id) else {
            return "Custom"
        }
        return preset.name
    }
}
