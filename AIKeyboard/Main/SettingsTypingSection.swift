import AIKeyboardCore
import SwiftUI

/// The "Typing" settings card: autocorrect, pause actions, auto-capitalise,
/// and predictions. Learned words and Forget live on Personal dictionary.
///
/// **Every switch here is affected by Full Access, not some of them.** Each
/// one is a `SharedStore.stored*` accessor the keyboard reads across the App
/// Group at the keystroke — `storedAutocorrectLevel`, `storedAutocapitalise`,
/// `storedPredictions`, `storedCompleteOnIdle`, `storedSpaceOnIdle`,
/// `storedIdleDelayMs` — so there is no row here to carve out as a survivor,
/// unlike `accountSection` on the same screen. See `FullAccessNeededBanner`.
struct SettingsTypingSection: View {
    @EnvironmentObject private var store: SharedStore
    let setup: SetupState

    /// How much evidence the space bar needs before it replaces a word.
    ///
    /// **The subtitle follows the selection instead of describing the control.**
    /// "High confidence" is a label, not an explanation, and the difference
    /// between the three positions is the entire reason this stopped being a
    /// switch: off keeps every keystroke, the middle keeps the repairs and drops
    /// the guesses, full is what the keyboard shipped with. A row that says the
    /// same sentence under all three tells the user nothing about the one they
    /// are on.
    @ViewBuilder private var autocorrectRow: some View {
        HStack(spacing: Theme.Space.sm) {
            IconBadge(systemName: "text.badge.checkmark")
            VStack(alignment: .leading, spacing: 2) {
                Text("Autocorrect")
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.Text.primary)
                Text(Self.autocorrectSubtitle(store.autocorrectLevel))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.Text.secondary)
            }
            Spacer(minLength: 0)
            Picker("Autocorrect", selection: $store.autocorrectLevel) {
                ForEach(AutocorrectLevel.allCases, id: \.self) { level in
                    Text(level.title).tag(level)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
    }

    private static func autocorrectSubtitle(_ level: AutocorrectLevel) -> String {
        switch level {
        case .off:
            return "Space keeps exactly what you typed"
        case .confident:
            return "Space fixes a clear slip. Everything else waits in the bar for a tap."
        case .full:
            return "Space inserts the bold word"
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

    /// Mirrors `LayoutView.fullAccessMessage`'s hedge: `setup.fullAccess` can
    /// only ever *confirm* a yes, so this says "once Full Access is on"
    /// rather than asserting it is off right now.
    private static let fullAccessMessage =
        "The keyboard can only read these once Full Access is on. Until then it keeps typing, "
        + "autocorrecting and predicting the way it shipped, whatever is set here."

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            if setup.fullAccess != .confirmed {
                FullAccessNeededBanner(message: Self.fullAccessMessage, context: "typing")
            }
            SectionHeader(title: "Typing")
            Card {
                VStack(spacing: Theme.Space.sm) {
                    autocorrectRow
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
