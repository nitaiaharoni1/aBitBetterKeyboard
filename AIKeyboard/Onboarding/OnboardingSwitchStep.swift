import AIKeyboardCore
import SwiftUI

/// The one setup fact iOS will never hand the app: which keyboard is on screen
/// in another process. `KeyboardPresence` proves the keyboard ran; this step
/// collects the user's own confirmation that they reached it with the globe
/// key, and persists that answer on the store. The row is `unknown`, never
/// `blocked`, because the app cannot distinguish "hasn't yet" from "did and
/// hasn't said".
struct SwitchStep: View {
    @EnvironmentObject private var store: SharedStore
    let setup: SetupState

    var body: some View {
        StepLayout(
            icon: "globe",
            eyebrow: "Setup",
            title: setup.switchAcknowledged ? "You're on the keyboard" : "Switch to it once",
            subtitle:
                "Open any app with a text field and tap the globe key until AI Keyboard appears. iOS never tells us which keyboard is showing, so this one is yours to confirm."
        ) {
            Card {
                StatusRow(
                    title: "Switched with the globe key",
                    detail: setup.keyboardSwitchedDetail,
                    check: setup.keyboardSwitched
                )
            }

            if !setup.switchAcknowledged {
                VStack(spacing: 0) {
                    ExplainerStepRow(
                        number: 1,
                        title: "Open any app with a text field",
                        detail: "Messages, Notes, anywhere you can type."
                    )
                    .padding(.vertical, Theme.Space.sm)

                    Divider.themed

                    ExplainerStepRow(
                        number: 2,
                        title: "Tap the globe key",
                        detail: "Keep tapping until AI Keyboard appears."
                    )
                    .padding(.vertical, Theme.Space.sm)

                    Divider.themed

                    ExplainerStepRow(
                        number: 3,
                        title: "Come back here",
                        detail: "Confirm with the button below."
                    )
                    .padding(.vertical, Theme.Space.sm)
                }
            }
        }
    }
}
