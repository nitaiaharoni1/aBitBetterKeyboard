import SwiftUI

extension KeyView {

    // MARK: Label

    @ViewBuilder
    var label: some View {
        switch spec.cap {
        case .character(let value):
            // The bottom row's punctuation key wears its long presses in
            // miniature above the mark it types. Everywhere else the popup is a
            // shortcut to something the user already knows is there — an accent
            // on the letter it belongs to — but this key's whole purpose is the
            // four marks that are not drawn on it, and a lone full stop is the
            // faintest cap on the keyboard. The hint is what says to hold it.
            // `addressableID`, not `id`: compiled from a custom layout this key is
            // `punctuation#a1b2c3d4`, and against the raw id the miniature marks
            // silently stopped being drawn.
            if spec.addressableID == KeyboardLayout.punctuationKeyID, !spec.alternates.isEmpty {
                VStack(spacing: 0) {
                    Text(spec.alternates.prefix(3).joined())
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(Theme.Keys.label.opacity(0.5))
                    Text(value)
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(Theme.Keys.label)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            } else {
                Text(shift.isUppercase ? language.uppercased(value) : value)
                    .font(.system(size: characterFontSize, weight: .light))
                    .foregroundStyle(Theme.Keys.label)
            }

        case .shift:
            // **The glyph is the entire shift state.** Outline at rest, filled
            // when on, capslock when latched — warm white on the deep graphite
            // cap in every case, so the fill of the arrow does the talking.
            Image(systemName: shift == .locked ? "capslock.fill" : (shift == .on ? "shift.fill" : "shift"))
                .font(Theme.Glyph.font(19))
                .foregroundStyle(labelColor)

        case .backspace:
            Image(systemName: "delete.left")
                .font(Theme.Glyph.font(19))
                .foregroundStyle(labelColor)

        case .plane(_, let text):
            Text(text)
                .font(.system(size: 16, weight: .light))
                .foregroundStyle(labelColor)
                .minimumScaleFactor(0.7)
                .lineLimit(1)

        case .globe:
            Image(systemName: "globe")
                .font(Theme.Glyph.font(18))
                .foregroundStyle(labelColor)

        case .settings:
            Image(systemName: "gearshape")
                .font(Theme.Glyph.font(18))
                .foregroundStyle(labelColor)

        case .space:
            spaceLabel

        case .ret:
            // The glyph in every language, never a word. Apple ships no localised
            // return-key cap — the only per-language string on the machine is
            // VoiceOver's phrasing ("Volver", "Клавиша «Ввод»"), not a key cap —
            // so a word here is either English on a Greek keyboard or a
            // translation nobody has checked. The arrow needs neither.
            Image(systemName: "return")
                .font(Theme.Glyph.font(17))
                .foregroundStyle(labelColor)

        case .dictation:
            // Outline, not `mic.fill`. A solid microphone reads as *recording* —
            // it is the shape the banner uses for exactly that — and this key is
            // the one that has not started yet.
            actionLabel(
                icon: "mic",
                title: "Dictate",
                tint: Theme.Brand.solid,
                showsCaption: showsActionCaption)

        case .emoji:
            // **One key, two jobs, and the cap is what says which.** With the grid
            // open this is the way back to the letters, so it wears the letters
            // plane's own label — `ABC`, `אבג`, `АБВ` — exactly as the `123` key
            // does when it is pointing home. The category row under the grid used
            // to carry a second `אבג` of its own; two keys a thumb's width apart
            // doing one job is what that was, and this is the one that survived
            // because it does not move when the grid opens.
            //
            // Neutral rather than brand in both states: `Theme.Brand` is reserved
            // for the AI moments, and this one opens a grid of pictures.
            if isEmojiOpen {
                Text(language.lettersPlaneLabel)
                    .font(.system(size: 16, weight: .light))
                    .foregroundStyle(labelColor)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            } else {
                actionLabel(
                    icon: "face.smiling",
                    title: "Emoji",
                    tint: Theme.Keys.label,
                    showsCaption: showsActionCaption)
            }

        case .quickTone:
            // `AIAction.rewrite`'s own icon, and never a sparkle in any count —
            // see `SuggestionBar.toneButtonSymbol` and `ToneIconTests` for the
            // pairing that has already shipped once.
            //
            // **The word matters more here than on any other key in the row.**
            // `arrow.triangle.2.circlepath` alone is a refresh glyph: it says
            // nothing about rewriting, nothing about AI, and it is the same
            // "a glyph is not a name" defect that has now been fixed twice on this
            // one control — first when it wore the tone's own symbol in the bar,
            // then when the tone name was moved under it. It does not name the
            // *tone* here, unlike the bar button it replaced, because the register
            // is a long press away and the label has to say what a tap does.
            actionLabel(
                icon: SuggestionBar.toneButtonSymbol,
                title: AIAction.rewrite.title,
                tint: Theme.Brand.solid)

        case .cursorLeft:
            Image(systemName: "arrow.left")
                .font(Theme.Glyph.font(17))
                .foregroundStyle(labelColor)

        case .cursorRight:
            Image(systemName: "arrow.right")
                .font(Theme.Glyph.font(17))
                .foregroundStyle(labelColor)

        case .hideKeyboard:
            Image(systemName: "keyboard.chevron.compact.down")
                .font(Theme.Glyph.font(17))
                .foregroundStyle(labelColor)

        case .aiReply:
            actionLabel(
                icon: AIAction.reply.icon, title: AIAction.reply.title, tint: Theme.Brand.solid)

        case .aiFix:
            actionLabel(
                icon: AIAction.fix.icon, title: AIAction.fix.title, tint: Theme.Brand.solid)
        }
    }

    // MARK: Action label

    /// An action drawn as a key: its glyph, and its name under it when there is
    /// room.
    ///
    /// Reply, Fix and Rewrite keep captions in the shipped action row. Emoji and
    /// Dictate deliberately use their familiar glyphs alone there, but regain
    /// captions when moved to another wide row.
    ///
    /// The tint `actionLabel` resolves, against the cap the key is wearing.
    ///
    /// On the dark caps — emoji and dictation — the glyph is the warm-white
    /// `labelOnFunction` at rest, because a brand tint on soft graphite is
    /// neither readable nor the neutral control that key is. On the light AI
    /// caps, custom placements keep each action's own brand tint while the
    /// shipped action row uses the same neutral label colour as the other keys.
    /// Under a finger every cap goes light and the glyph goes graphite, exactly
    /// as `KeyView.labelColor` has it.
    ///
    /// A function rather than an `if` inside the `@ViewBuilder` below: a branch
    /// statement in a builder body is parsed as view content, not as flow.
    func actionTint(_ tint: Color) -> Color {
        if isPressed { return Theme.Keys.label }
        if restsOnDarkCap && !isActionActive { return Theme.Keys.labelOnFunction }
        return usesNeutralActionTint ? Theme.Keys.label : tint
    }

    @ViewBuilder
    func actionLabel(
        icon: String,
        title: String,
        tint: Color,
        showsCaption: Bool = true
    ) -> some View {
        let resolvedTint = actionTint(tint)

        if showsCaption, width >= Self.captionMinimumWidth {
            VStack(spacing: 1) {
                Image(systemName: icon)
                    .font(Theme.Glyph.medium(15))
                Text(title)
                    .font(Font(SuggestionBar.toneLabelFont))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(resolvedTint)
            .padding(.horizontal, Theme.Space.xxs)
        } else {
            Image(systemName: icon)
                .font(Theme.Glyph.medium(16))
                .foregroundStyle(resolvedTint)
        }
    }
}
