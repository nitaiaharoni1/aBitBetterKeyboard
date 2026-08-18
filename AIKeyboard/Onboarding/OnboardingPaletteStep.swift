import AIKeyboardCore
import SwiftUI

/// **It used to be the second step so that the eight screens after it were
/// drawn in the colour just chosen. There are no longer eight screens after
/// anything**, so that argument no longer buys a place on the required path and
/// this became the first of `OnboardingStep.extras` instead. The recolouring
/// still works from here — `RootView`'s brand `id` rebuilds the tab tree, and
/// the flow's own rebuilds the remaining steps — it just has less left to do.
///
/// The only step with no `SetupState`. Nothing about a colour can be verified
/// outside the app, and there is nothing here to skip: a palette is always set,
/// because `orange` is the shipped default and the step opens on it. Skip is
/// offered anyway now, rather than suppressed as a special case, because on an
/// optional screen "Skip" and "Continue" doing the same thing is honest — the
/// user asked to see this, and either button takes them onward.
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

            Text("You can change this later in Keys.")
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Text.tertiary)
        }
    }
}
