import AIKeyboardCore
import SwiftUI

struct AddKeyboardStep: View {
    let setup: SetupState

    var body: some View {
        StepLayout(
            icon: "keyboard",
            eyebrow: "Setup",
            title: setup.keyboardAdded == .confirmed ? "The keyboard is added" : "Add the keyboard",
            subtitle: setup.keyboardAdded == .confirmed
                ? "We can see it, so there is nothing to do here."
                : "iOS keeps custom keyboards behind Settings. It takes about twenty seconds."
        ) {
            Card {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    StatusRow(
                        title: "Keyboard added",
                        detail: setup.keyboardAddedDetail,
                        check: setup.keyboardAdded
                    )

                    Divider.themed

                    StatusRow(
                        title: "Allow Full Access",
                        detail: setup.fullAccessDetail,
                        check: setup.fullAccess
                    )
                }
            }

            if setup.keyboardAdded != .confirmed {
                VStack(spacing: 0) {
                    ExplainerStepRow(
                        number: 1,
                        title: "Open Settings",
                        detail: "Then tap General."
                    )
                    .padding(.vertical, Theme.Space.sm)

                    Divider.themed

                    ExplainerStepRow(
                        number: 2,
                        title: "Tap Keyboard",
                        detail: "Then tap Keyboards."
                    )
                    .padding(.vertical, Theme.Space.sm)

                    Divider.themed

                    ExplainerStepRow(
                        number: 3,
                        title: "Tap Add New Keyboard…",
                        detail: "AI Keyboard is listed under Third-Party Keyboards."
                    )
                    .padding(.vertical, Theme.Space.sm)

                    Divider.themed

                    ExplainerStepRow(
                        number: 4,
                        title: "Choose AI Keyboard",
                        detail: "Then come back to this app."
                    )
                    .padding(.vertical, Theme.Space.sm)
                }

                // The numbered rows above carry the path from the top of
                // Settings; this button promises nothing more than getting there.
                SecondaryButton(title: "Open Settings", action: openSettings)

                Text(
                    "Both rows tick themselves once you have switched to the keyboard in any app. Until then the app genuinely cannot tell."
                )
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Text.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
