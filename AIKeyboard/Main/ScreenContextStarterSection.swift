import AIKeyboardCore
import SwiftUI

/// The "Start screen context" (or "Start it again") card with numbered steps
/// and the system broadcast picker button.
///
/// `RPSystemBroadcastPickerView` cannot be triggered programmatically, so
/// there is no "Start" button here that does the work — the three steps say
/// what the user has to do, and the button below them is the system's own.
struct ScreenContextStarterSection: View {
    let source: ScreenContextSession.Source

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            SectionHeader(title: source == .capture ? "Start it again" : "Start screen context")

            Card {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    ExplainerStepRow(
                        number: 1, title: "Tap the button below",
                        detail: "iOS opens its own list of what can record the screen.")
                    ExplainerStepRow(
                        number: 2, title: "Pick AI Keyboard, then Start Broadcast",
                        detail: "iOS counts down from three before anything starts.")
                    ExplainerStepRow(
                        number: 3, title: "Go back to your conversation",
                        detail:
                            "A red indicator stays in the status bar for as long as this runs. Tap it to stop."
                    )

                    HStack {
                        Spacer()
                        BroadcastPickerButton()
                            .accessibilityLabel("Start a screen broadcast")
                            .accessibilityIdentifier("screen-context-start-broadcast")
                        Spacer()
                    }

                    Text("Only iOS can start this. No app can press that button for you, including this one.")
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Text.tertiary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
