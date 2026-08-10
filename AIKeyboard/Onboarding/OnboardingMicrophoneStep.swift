import AIKeyboardCore
import SwiftUI

struct MicrophoneStep: View {
    let setup: SetupState

    @State private var pulse = false

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

            HStack {
                Spacer()
                ZStack {
                    Circle()
                        .fill(Theme.Brand.softGradient)
                        .frame(width: 132, height: 132)
                        .scaleEffect(pulse ? 1.08 : 0.94)

                    Circle()
                        .fill(Theme.Brand.gradient)
                        .frame(width: 88, height: 88)

                    Image(systemName: "mic.fill")
                        .font(.system(size: 34, weight: .medium))
                        .foregroundStyle(Theme.Text.onBrand)
                }
                Spacer()
            }
            .padding(.vertical, Theme.Space.sm)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
            .accessibilityHidden(true)

            Card {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text("Why it is split in two")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.Text.primary)
                    Text(
                        "Apple isolates keyboard extensions from the microphone. Every voice keyboard on iOS works this way, and it is the part of the product most likely to change with an iOS update."
                    )
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.Text.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
