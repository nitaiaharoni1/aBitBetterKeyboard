import AIKeyboardCore
import SwiftUI

/// The "Typing" settings card: autocorrect, auto-capitalise, predictions,
/// number row, and keyboard layout.
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
                Text(
                    "Measured: the right word is chosen \(measured.english)% of the time in English, "
                        + "\(measured.hebrew)% in Hebrew. Hold a key to pick one letter exactly."
                )
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Text.secondary)
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            SectionHeader(title: "Typing")
            Card {
                VStack(spacing: Theme.Space.sm) {
                    ToggleRow(
                        title: "Autocorrect",
                        subtitle: "Commits the bold suggestion when you press space",
                        icon: "text.badge.checkmark",
                        isOn: $store.autocorrect
                    )
                    Divider.themed
                    ToggleRow(
                        title: "Auto-capitalise",
                        icon: "textformat",
                        isOn: $store.autocapitalise
                    )
                    Divider.themed
                    ToggleRow(
                        title: "Predictions",
                        subtitle: "Show the suggestion bar above the keys",
                        icon: "lightbulb",
                        isOn: $store.predictions
                    )
                    Divider.themed
                    ToggleRow(
                        title: "Learn as you type",
                        subtitle: learningSubtitle,
                        icon: "brain",
                        isOn: $store.learnsFromTyping
                    )
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
                    Divider.themed
                    ToggleRow(
                        title: "Number row",
                        subtitle: "Digits above the letters. Makes the keyboard taller.",
                        icon: "textformat.123",
                        isOn: numberRowBinding
                    )
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
