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
        /// Nothing to rewrite. The tap says so in the banner rather than opening
        /// anything — the menu this used to be a shortcut through is deleted, and a
        /// tap that draws nothing is precisely the defect this enum's third case
        /// exists to prevent.
        case needsText
        /// A call is already in flight. `beginWork` cancels its predecessor, so a
        /// second tap would throw away the answer being waited on — and this is
        /// the one state where ignoring a tap is honest, because the button is
        /// showing a spinner rather than an icon.
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
    /// carrying — which of six tones a tap runs, otherwise unknowable without
    /// opening a panel — is real and is kept, just moved into the label under the
    /// glyph where it can be read rather than guessed. `ToneStyle.icon` is still the
    /// per-tone symbol and still used, in the tone picker and on a result variant,
    /// where the surrounding panel already says what the screen is about.
    ///
    /// `KeyboardController.runDefaultTone` carries why this is Rewrite and not Fix.
    ///
    /// Three states, and they look like three things. With something to rewrite it
    /// is brand-tinted and lit. With nothing to rewrite the gradient goes and the
    /// icon drops to `secondaryLabel`, so it is drawn exactly like the inactive
    /// emoji button at the other end of this bar and cannot be mistaken for its
    /// lit neighbour — and it stays tappable, because a control that looks
    /// unavailable and swallows the tap teaches the user nothing. A call in flight
    /// replaces the icon with a spinner and is the only state that disables it. A
    /// call that *failed* needs nothing here: `beginWork` puts the reason in
    /// `aiError` and `ActionBanner` is already showing it, one row up.
    var toneButton: some View {
        let tone = controller.defaultTone
        let isBusy = controller.isWorking
        let tap = Self.toneTap(
            hasTextToWorkWith: controller.hasTextToWorkWith, isWorking: isBusy)

        let tint = tap == .rewrite ? Theme.Brand.solid : Theme.Keys.secondaryLabel

        return Button {
            switch tap {
            case .rewrite: controller.runDefaultTone()
            case .needsText:
                // The bar's own button, which is not a key, so nothing has
                // acknowledged the tap yet.
                Feedback.actionPress()
                controller.refuseForEmptyField(.rewrite)
            case .ignore: break
            }
        } label: {
            // The spinner replaces the glyph and not the label: a bare spinner in
            // a 68pt slot is an unlabelled box, and the button is being waited on
            // precisely when the user most wants to know what they tapped.
            VStack(spacing: 1) {
                Group {
                    if isBusy {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(Theme.Brand.solid)
                    } else {
                        Image(systemName: Self.toneButtonSymbol)
                            .font(Theme.Glyph.medium(15))
                            .foregroundStyle(tint)
                    }
                }
                .frame(height: 18)

                Text(tone.title)
                    .font(Font(Self.toneLabelFont))
                    .foregroundStyle(tint)
                    .lineLimit(1)
            }
            .padding(.horizontal, Self.toneButtonInset)
            .frame(width: Self.toneButtonWidth, height: 40)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                    .fill(Theme.Brand.softGradient)
                    .opacity(tap == .rewrite ? 1 : 0)
            )
            .contentShape(Rectangle())
        }
        .pressable()
        .disabled(tap == .ignore)
        .accessibilityIdentifier("bar-tone")
        .accessibilityLabel("Rewrite as \(tone.title)")
        .accessibilityHint(toneHint(tap))
    }

    private func toneHint(_ tap: ToneTap) -> String {
        switch tap {
        case .ignore: return "Working"
        case .needsText: return "Nothing to rewrite yet. Says what to do about it"
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
