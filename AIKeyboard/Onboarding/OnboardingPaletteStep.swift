import AIKeyboardCore
import SwiftUI

/// Second step, and deliberately the second rather than the last: everything
/// after it — the progress bar, the Continue button, the eyebrow on each of the
/// five setup steps, and the live keyboard the practice stages embed — is drawn
/// in whatever was chosen here. Put at the end it would have recoloured three
/// screens instead of eight.
///
/// The only step with no `SetupState`. Nothing about a colour can be verified
/// outside the app, and there is nothing here to skip: a palette is always set,
/// because `orange` is the shipped default and the step opens on it.
struct PaletteStep: View {
    var body: some View {
        StepLayout(
            icon: "paintpalette",
            eyebrow: "Make it yours",
            title: "Pick your accent",
            subtitle:
                "One colour, used for buttons, the AI moments and the keys that are doing something. The keys themselves stay the shade iOS draws them."
        ) {
            Card(padding: Theme.Space.sm) {
                PalettePicker()
            }

            Text("You can change this later in Settings.")
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Text.tertiary)
        }
    }
}
