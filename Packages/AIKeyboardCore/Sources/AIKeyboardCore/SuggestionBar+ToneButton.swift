import SwiftUI

extension SuggestionBar {

    // MARK: One-tap rewrite

    /// What a tap on the one-tap rewrite button does, in every state it has.
    ///
    /// **The point of the enum is that there is no fourth case for "nothing".**
    /// The button shipped `.disabled(!canRun)` with a brand gradient behind a
    /// fully-saturated brand-coloured icon: only the *background* faded, so beside
    /// the fully-lit sparkle it read as live, and on an empty field — which is
    /// most of the time, because a keyboard comes up on an empty field — a tap on
    /// it did nothing at all and said nothing about why.
    enum ToneTap: Equatable {
        case rewrite
        /// Nothing to rewrite.
        ///
        /// **It used to answer the tap with a sentence in the banner, and now it
        /// takes no tap at all.** The rule this case was written under — that a
        /// control which looks unavailable and swallows the tap teaches the user
        /// nothing — was learned from a button that looked *live*: a fully
        /// saturated brand icon over a faded gradient, which read as enabled and
        /// then did nothing. The answer to that is to look unavailable, which is
        /// what this state does now on both surfaces at once: this button and the
        /// Rewrite key beside Fix in the action row are drawn dim and disabled
        /// together. See `KeyboardController.isActionKeyDisabled`. The words did not
        /// disappear with the banner — they are the accessibility hint, where they
        /// reach the person who cannot see that the control is off.
        case needsText
        /// A call is already in flight. `beginWork` cancels its predecessor, so a
        /// second tap would throw away the answer being waited on — and this is
        /// the one state where ignoring a tap is honest, because the button is
        /// already the thing being waited on.
        case ignore
    }

    static func toneTap(hasTextToWorkWith: Bool, isWorking: Bool) -> ToneTap {
        if isWorking { return .ignore }
        return hasTextToWorkWith ? .rewrite : .needsText
    }

    /// The glyph the one-tap button always wears, whatever the tone is.
    ///
    /// **It is `AIAction.rewrite`'s own icon on purpose.** The button is a
    /// shortcut to the Rewrite action, so drawing what that action draws is the
    /// only thing in the bar that says which action it runs.
    /// It must not be a sparkle in any count: `SparkleMark` sits against it with no
    /// rule between them, and that pairing has already shipped once — see
    /// `ToneIconTests`.
    static let toneButtonSymbol = AIAction.rewrite.icon

    /// The one-tap button's width, the same for every tone.
    ///
    /// **Fixed rather than grown to fit, because the label under the glyph is a
    /// setting and a button that resizes when a setting changes moves its
    /// neighbours with it.** Letting it size to its text put `Professional` at 67pt
    /// against `Casual`'s 44, so changing the default tone in Settings silently
    /// re-laid-out the suggestion bar — three candidates the user reads mid-word,
    /// shifted sideways by a choice made on another screen.
    ///
    /// 68 is the widest label plus the padding, so nothing ever scales down:
    /// `Professional` measures 56.6pt at this font and the inset is 5 a side.
    /// `ToneIconTests` holds every tone name to fitting, which is the assertion
    /// that fails if a seventh register arrives with a longer name.
    static let toneButtonWidth: CGFloat = 68

    /// The inset either side of the label inside `toneButtonWidth`.
    static let toneButtonInset: CGFloat = 5

    /// The label's type, as a `UIFont` so the width rule can be measured against
    /// the font the button actually draws rather than against a second spelling of
    /// it. The view wraps it back into a `Font`.
    ///
    /// Semibold at 9pt, against the `Theme.Glyph` light house weight the icons use:
    /// a hairline holds up at 15pt and disappears at 9.
    static let toneLabelFont = UIFont.systemFont(ofSize: 9, weight: .semibold)

    /// Rewrite in the default tone, without opening anything.
    ///
    /// **The icon is fixed and the tone is written out under it, because the icon
    /// alone answered the wrong question.** It used to be the tone's own symbol and
    /// nothing else, so a user with Casual selected got a small waving stick figure
    /// (`figure.wave`) in a keyboard, which says nothing about rewriting, nothing
    /// about AI, and reads as a profile or contacts button. The fact it *was*
    /// carrying — which tone a tap runs, otherwise unknowable without
    /// opening a panel — is real and is kept, just moved into the label under the
    /// glyph where it can be read rather than guessed. `ToneStyle.icon` is still the
    /// per-tone symbol and still used, in the tone picker and on a result variant,
    /// where the surrounding panel already says what the screen is about.
    ///
    /// `KeyboardController.runDefaultTone` carries why this is Rewrite and not Fix.
    ///
    /// Three states, and they look like three things. With something to rewrite it
    /// is brand-tinted and lit. With nothing to rewrite the gradient goes and the
    /// glyph fades to the same `KeyView.disabledLabelOpacity` the Rewrite key in
    /// the action row fades to, and it takes no tap — the two are one control in
    /// two places and used to disagree about what an empty field means, which is
    /// D8's own defect. A rewrite or tone call in flight keeps the icon and
    /// sweeps the filled cap; Fix and Reply leave this button alone and light
    /// their own keys. A call that *failed* needs nothing here: `beginWork` puts
    /// the reason in `aiError` and `ActionBanner` is already showing it, one row
    /// up.
    ///
    /// **The question is asked of `isActionKeyDisabled` rather than of
    /// `documentHasText`, so this button and the Rewrite key cannot answer it
    /// differently.** They used to each read the field for themselves, which is
    /// D8's own defect, and the reasons a control is unavailable have since grown:
    /// an empty field is one, and a recording in progress is another — nothing may
    /// edit a message while it is still being spoken into. Reading the same
    /// published question keeps the two in step by construction rather than by
    /// both remembering to add the new clause.
    var toneButton: some View {
        let tone = controller.defaultTone
        let isBusy = controller.isWorking
        let tap = Self.toneTap(
            hasTextToWorkWith: !controller.isActionKeyDisabled(.quickTone), isWorking: isBusy)
        let activity = KeyActivity.resolveTone(
            runningAction: controller.runningAction,
            isWorking: isBusy,
            workingPhase: controller.workingPhase)
        let isToneWorking = activity != .idle

        let tint: Color = {
            if isToneWorking { return Theme.Text.onBrand }
            if tap == .rewrite { return Theme.Brand.solid }
            return Theme.Keys.label.opacity(KeyView.disabledLabelOpacity)
        }()

        return Button {
            // Only one state can be reached by a tap now; the other two are
            // disabled below. Left as a switch rather than a call so that adding a
            // fourth state has to answer this question rather than inherit an
            // answer.
            switch tap {
            case .rewrite: controller.runDefaultTone()
            case .needsText, .ignore: break
            }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                    .fill(Theme.Brand.action)
                    .opacity(isToneWorking ? 1 : 0)
                RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                    .fill(Theme.Brand.softGradient)
                    .opacity(tap == .rewrite && !isToneWorking ? 1 : 0)
                ControlActivityChrome(activity: activity, cornerRadius: Theme.Radius.chip)
                VStack(spacing: 1) {
                    Image(systemName: Self.toneButtonSymbol)
                        .font(Theme.Glyph.medium(15))
                        .frame(height: 18)
                    Text(tone.title)
                        .font(Font(Self.toneLabelFont))
                        .lineLimit(1)
                }
                .foregroundStyle(tint)
                .padding(.horizontal, Self.toneButtonInset)
            }
            .clipShape(
                RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
            )
            .frame(width: Self.toneButtonWidth, height: 40)
            .contentShape(Rectangle())
        }
        .pressable()
        .disabled(tap != .rewrite)
        .accessibilityIdentifier("bar-tone")
        .accessibilityLabel(
            isToneWorking
                ? "\(controller.runningAction?.title ?? AIAction.rewrite.title), working"
                : "Rewrite as \(tone.title)"
        )
        .accessibilityHint(toneHint(tap))
    }

    private func toneHint(_ tap: ToneTap) -> String {
        switch tap {
        case .ignore: return "Working"
        // Two reasons wear this one case, so the words come from the same place
        // the key's own hint reads them from rather than being spelled here — a
        // button that says "type something first" over a live recording is telling
        // the user to do the one thing they are already doing.
        case .needsText: return controller.actionKeyDisabledReason(.quickTone)
        // The same words `ToneSetting.settingsNote` points at this button with, so
        // "the one-tap rewrite button" names one control everywhere it is written.
        case .rewrite:
            return "The one-tap rewrite button. Rewrites what you typed in your default tone"
        }
    }

    /// Kept although the sparkle that read it is gone: `SuggestionBar+Edges` still
    /// asks the same question of `AIAction`, and the two must not drift apart again.
    var isEnabled: Bool {
        Self.anyActionCouldRun(hasTextToWorkWith: controller.hasTextToWorkWith)
    }
}
