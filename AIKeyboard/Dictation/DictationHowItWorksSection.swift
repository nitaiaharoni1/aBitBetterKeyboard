import AIKeyboardCore
import SwiftUI

/// The "How dictation works" card: four numbered steps and a privacy note.
///
/// Takes `sessionMinutes` as a plain value (not a binding) because this card
/// is informational — it shows the configured limit but does not change it.
struct DictationHowItWorksSection: View {
    let sessionMinutes: Int

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                SectionHeader(title: "How dictation works")

                ExplainerStepRow(
                    number: 1,
                    title: "Start the session here",
                    detail:
                        "iOS won't let a keyboard open the microphone, and won't let an app start recording from the background. So it starts here, with AI Keyboard in front of you."
                )
                ExplainerStepRow(
                    number: 2,
                    title: "Switch to the app you're writing in",
                    detail:
                        "The session keeps running while AI Keyboard is in the background. iOS shows the orange microphone dot the whole time it does."
                )
                ExplainerStepRow(
                    number: 3,
                    title: "Tap the microphone on the keyboard",
                    detail:
                        "Speak, then tap Insert. The recording is transcribed and the words go straight into the field."
                )
                ExplainerStepRow(
                    number: 4,
                    title: "It closes itself",
                    detail:
                        "After \(sessionMinutes) minutes, or when you stop it here, or if a call takes the microphone."
                )

                Divider().overlay(Theme.Surface.separator)

                Text(
                    "Nothing is recorded between taps, and no recording is ever written to disk. What is kept is the text, until the session ends."
                )
                .font(.system(size: 12))
                .foregroundStyle(Theme.Text.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
