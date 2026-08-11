import SwiftUI
import AIKeyboardCore

struct PlaygroundView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Seeded with something worth fixing. An empty playground gives
                // the AI actions nothing to act on, so the first tap does nothing
                // and the feature looks broken.
                //
                // Which is exactly why the instruction cannot be "type a
                // sentence": the sentence is already typed, so the one thing the
                // screen told the user to do was the one thing already done. The
                // hint names what to do *with* it, and `KeyboardPreview` drops it
                // the moment the text stops being the seed. The placeholder is a
                // different sentence for a different state — it is only ever seen
                // once the user has cleared the field, and then typing really is
                // the next thing.
                KeyboardPreview(
                    seedText: PlaygroundView.seedSentence,
                    placeholder: PlaygroundView.seedPlaceholder,
                    hint: PlaygroundView.seedHint
                )
            }
            .background(Theme.Surface.background)
            .navigationTitle("Playground")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(Theme.Fonts.body.weight(.semibold))
                }
            }
        }
    }

    /// Shared with onboarding's last step so the two places that hand the user a
    /// keyboard hand them the same sentence and the same next move.
    ///
    /// **Both name the button rather than drawing it.** These said "tap ✨" above a
    /// bar carrying two brand-tinted buttons side by side, the left one wearing the
    /// default tone's own icon — which was SF `sparkle`, the same drawing as the
    /// menu's `sparkles`. `ToneSetting.settingsNote` fixed exactly this in Settings
    /// and these two were left behind; the name now comes from
    /// `SuggestionBar.aiButtonName`, so there is one spelling of it.
    static let seedSentence = "i dont think we should do it because its not make sense"
    static let seedPlaceholder =
        "Type in Hebrew or English, then use \(SuggestionBar.aiButtonName)"
    /// **One tap, not two, and the actions are named because they are on screen
    /// now.** This used to say "tap ✨, then Fix", which was the panel flow: the
    /// sparkle opened a menu and Fix was a row inside it. Fix and Rewrite are keys
    /// in the action row, so the instruction that matches what the user is looking
    /// at is the name of the key.
    static let seedHint =
        "This sentence has mistakes in it on purpose. Tap Fix in \(SuggestionBar.aiButtonName) to "
        + "correct it, or Rewrite to say it another way."
}
