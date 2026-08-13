import AIKeyboardCore
import SwiftUI

/// The "Typing" settings card: autocorrect, pause actions, auto-capitalise,
/// predictions, and learn as you type.
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

    /// True of `PersonalLanguageModel`: unigrams and bigrams, local file, thresholds,
    /// no credential fields, App Group so Full Access is required to read it.
    private let learningDetail =
        "It counts how often you type a word, and which word usually comes next. Nothing longer than a pair is stored. The file stays on this device and is never uploaded. A word has to be typed a few times before it changes suggestions or is protected from autocorrect. Nothing is recorded in password fields. The keyboard needs Full Access to read that file."

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
                    LearnMoreDisclosure(detail: learningDetail)
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
                }
            }
        }
        .onAppear { learnedWordCount = PersonalLanguageModel.shared.learnedWordCount }
    }
}
