import AIKeyboardCore
import SwiftUI

/// The "Typing" settings card: autocorrect, pause actions, auto-capitalise,
/// and predictions. Learned words and Forget live on Personal dictionary.
struct SettingsTypingSection: View {
    @EnvironmentObject private var store: SharedStore

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
                }
            }
        }
    }
}
