import SwiftUI

extension SuggestionBar {

    // MARK: Bar edge catalogue

    /// What the bar's two ends may hold.
    ///
    /// A subset of `SlotAction.catalogue`, and the exclusions are the point. A
    /// space bar or a shift key 46 points tall above the letters is not a layout
    /// anybody meant to build. Delete is out for a subtler reason: it is the one
    /// key with an accelerating repeat, and the repeat is wired in `KeyView`,
    /// which does not draw this bar — an edge button would delete once per tap and
    /// look broken beside the real one.
    public static let barCatalogue: [SlotAction] = [
        .emoji, .quickTone, .dictation, .cursorLeft, .cursorRight,
        .hideKeyboard, .globe
    ]

    /// Where to send a reader looking for the AI actions, named once.
    ///
    /// For the reason `ToneSetting.settingsNote` gives: a glyph is not a name. The
    /// playground and onboarding both said "tap ✨" while two brand-tinted buttons
    /// sat side by side in this bar — and the default tone's own icon was SF
    /// `sparkle` next to this one's `sparkles`, so the instruction pointed at
    /// whichever of the two the reader looked at first.
    ///
    /// **It now names a row rather than a button, because the buttons moved and
    /// there is more than one of them.** Reply, Fix, Rewrite and dictation are keys
    /// in the action row under the keyboard, and the bar's own ends ship empty. It
    /// deliberately does not say "the sparkle": on a stock install there is no
    /// sparkle, and a user who has put one back in the bar through the layout
    /// editor is not who this copy is written for.
    public static let aiButtonName = "the action row under the keys"

    /// Whether any AI action could run right now.
    ///
    /// **Kept after the sparkle it was named for was deleted**, because the question
    /// was never about that button: the bar answering it differently from the
    /// actions themselves is D8, and `AIAction` is now the one place that answers.
    static func anyActionCouldRun(hasTextToWorkWith: Bool) -> Bool {
        AIAction.hasRunnableAction(hasTextToWorkWith: hasTextToWorkWith)
    }

    // MARK: Slot button

    /// One configured control.
    ///
    /// The two that keep their own views carry a measured decision each: the tone
    /// button's three-way tap, and the emoji key's active tint. Everything else is
    /// the same tap the grid key makes, so a control cannot behave differently
    /// depending on which of the two places the user put it.
    @ViewBuilder
    func slotButton(_ action: SlotAction) -> some View {
        switch action {
        case .emoji:
            // `isEmoji` rather than `== .emoji`, so the button stays lit and stays
            // a way out while the search box is open. Against the bare case it
            // went dark the moment the user tapped search, which reads as the grid
            // having been closed by something the user did not do.
            edgeButton(
                systemImage: "face.smiling", label: "Emoji",
                isActive: controller.overlay.isEmoji
            ) {
                controller.show(controller.overlay.isEmoji ? .none : .emoji)
            }
        case .quickTone:
            toneButton
        default:
            // Guarded rather than defaulted. `keyCap` answers non-nil for every
            // case today, and a `?? .space` here would mean a future gap types a
            // space into the user's message rather than drawing nothing.
            if let cap = action.keyCap(language: controller.language) {
                edgeButton(
                    systemImage: action.glyph ?? "questionmark",
                    label: action.title,
                    isActive: false
                ) {
                    controller.press(cap)
                }
            }
        }
    }

    fileprivate func edgeButton(
        systemImage: String,
        label: String,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(Theme.Glyph.font(19))
                .foregroundStyle(isActive ? Theme.Brand.solid : Theme.Keys.secondaryLabel)
                .frame(width: 44, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                        .fill(isActive ? Theme.Brand.solid.opacity(0.14) : .clear)
                )
                .contentShape(Rectangle())
        }
        .pressable()
        .accessibilityIdentifier("bar-\(label.lowercased())")
        .accessibilityLabel(label)
    }
}
