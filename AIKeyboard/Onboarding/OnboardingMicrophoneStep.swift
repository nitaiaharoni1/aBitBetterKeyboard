import AIKeyboardCore
import SwiftUI

struct MicrophoneStep: View {
    let setup: SetupState

    /// **The architecture this step used to say was unbuilt is now the one that
    /// ships**, and the step describes it rather than apologising for it. Recording
    /// happens in this app, the transcript crosses the App Group, the keyboard
    /// inserts it — see `DictationChannel` for why that shape is forced. The one
    /// thing that has not changed is that there is no button here: the microphone
    /// is asked for when a session starts, not during onboarding, because a
    /// permission prompt for something the user has not tried yet is the one they
    /// say no to.
    var body: some View {
        StepLayout(
            icon: "mic.fill",
            eyebrow: "Dictation",
            title: "About dictation",
            subtitle:
                "iOS does not let a keyboard open the microphone, so AI Keyboard holds it for you. Start a session on the Dictation screen, switch to whatever you are writing in, and the mic key on the keyboard works until the session closes."
        ) {
            Card {
                StatusRow(
                    title: "Microphone",
                    detail: setup.microphoneDetail,
                    check: setup.microphoneAccess
                )
            }

            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text("Why it is split in two")
                    .font(Theme.Fonts.headline)
                    .foregroundStyle(Theme.Text.primary)
                Text(
                    "Apple isolates keyboard extensions from the microphone. Every voice keyboard on iOS works this way, and it is the part of the product most likely to change with an iOS update."
                )
                .font(Theme.Fonts.callout)
                .foregroundStyle(Theme.Text.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
