import AIKeyboardCore
import SwiftUI

struct TryItStep: View {
    let setup: SetupState

    /// "The same keyboard you just installed" is true only for the user who did
    /// the two Settings steps; "Skip for now" is on both of them, so the other
    /// path reaches this screen having installed nothing. The app can tell which,
    /// so it says which — and the skipped version has to make clear that this
    /// preview is not the keyboard appearing in other apps yet, or the next
    /// disappointment is discovering it is not there.
    private var subtitle: String {
        setup.keyboardAdded == .confirmed
            ? "The same keyboard you just installed, running inside the app."
            : "The keyboard itself, running inside the app. It will not appear in other apps until "
                + "it is added in Settings, but you can try it here now."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text("Try it here first")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(Theme.Text.primary)

                // Describes the screen; it does not instruct. The instruction is
                // the hint inside `KeyboardPreview`, which names what to do with
                // the sentence already sitting there and disappears once the user
                // has done something with it. Telling somebody to "type a
                // sentence" above a sentence is the defect this replaced.
                Text(subtitle)
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.Text.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Theme.Space.lg)
            .padding(.top, Theme.Space.xl)

            KeyboardPreview(
                seedText: PlaygroundView.seedSentence,
                placeholder: PlaygroundView.seedPlaceholder,
                hint: PlaygroundView.seedHint
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .padding(.horizontal, Theme.Space.xs)
        }
    }
}
