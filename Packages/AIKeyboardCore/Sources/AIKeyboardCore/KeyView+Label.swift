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
            } else if !spec.groupedLines.isEmpty {
                groupedLabel(spec.groupedLines, size: groupedFontSize(value))
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
            // **This key is the whole of the recording notice now**, so it has two
            // appearances: waves at rest, pause while the microphone is on. The
            // × that cancelled a transcription in flight is gone. The glyph, the
            // word and the record-red cap are all resolved from one value — see
            // `DictationKeyState` and `KeyView.capKind` — so the key can never end
            // up filled red while captioned Record.
            actionLabel(
                icon: dictationState.icon,
                title: dictationState.title,
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
            // Neutral rather than brand in both label states: `Theme.Brand` is
            // reserved for the AI moments, and this one opens a grid of pictures.
            //
            // **That is about the tint at rest, and the cap while the grid is open
            // is a separate question with a different answer.** Every control in
            // this row that is *currently doing something* wears the filled brand
            // cap — see `KeyView.capKind` — and an open emoji grid is one of them,
            // so this key fills like the rest rather than being the one active
            // control drawn differently from its four neighbours. What stays true
            // is that nothing about emoji is brand-tinted when it is not open.
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

    /// A grouped cap: its letters in the shape they had on the keyboard it
    /// replaced, the top row's on the top line and the ones that were underneath
    /// underneath.
    ///
    /// **One `Text` per letter, and that is not a detail.** Drawn as a single
    /// string, `קר` is one right-to-left run: the bidi algorithm puts ר to the
    /// *left* of ק while the keys underneath have ק on the left, so every Hebrew
    /// cap would draw mirrored — the defect that shipped six right-to-left layouts
    /// backwards once already, in a place no row-order test can see, because the
    /// row would be right and only the cap reversed. Separate views also mean the
    /// gaps between letters are laid out rather than kerned, so the last letter of
    /// a line cannot be tracked off the edge of its own key.
    ///
    /// **Each letter occupies an equal cell that fills the key.** A clustered
    /// HStack (`spacing: size * 0.34` around intrinsically sized glyphs) left
    /// `ו` looking like a skinny button beside `קר` on caps the width solver had
    /// already made equal — the same shape as weighting `.share` by span, in the
    /// one place that test cannot see, because it reads the solved widths. Hit
    /// testing already splits the cap into equal cells; the drawing has to match.
    @ViewBuilder
    func groupedLabel(_ lines: [[String]], size: CGFloat) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Group {
                    if line.isEmpty {
                        // An empty HStack collapses; a clear view still takes its
                        // slice, which is how `ךף` stays on the lower half.
                        Color.clear
                    } else {
                        HStack(spacing: Self.groupedLetterSpacing) {
                            ForEach(Array(line.enumerated()), id: \.offset) { _, letter in
                                Text(shift.isUppercase ? language.uppercased(letter) : letter)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .font(.system(size: size, weight: .light))
        .foregroundStyle(Theme.Keys.label)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        // The letters are a picture of the keyboard, so they run in the order the
        // keyboard does whatever the script does. Same pin every key row carries.
        .environment(\.layoutDirection, .leftToRight)
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
    /// On the dark caps — emoji at rest — the glyph is the warm-white
    /// `labelOnFunction`, because a brand tint on soft graphite is neither
    /// readable nor the neutral control that key is. On the light AI caps,
    /// custom placements keep each action's own brand tint while the shipped
    /// action row uses the same neutral label colour as the other keys. Under a
    /// finger every cap goes light and the glyph goes graphite, exactly as
    /// `KeyView.labelColor` has it.
    ///
    /// A function rather than an `if` inside the `@ViewBuilder` below: a branch
    /// statement in a builder body is parsed as view content, not as flow.
    /// White on every filled brand or record cap, keyed off `capKind` rather
    /// than `isActionActive`. The microphone wears that cap at rest (orange)
    /// and while recording (red), so a brand-tinted glyph would be orange on
    /// orange — the same fill/glyph disagreement `KeyView.capKind` exists to
    /// prevent.
    func actionTint(_ tint: Color) -> Color {
        if isPressed { return Theme.Keys.label }
        if capKind == .action || capKind == .record { return Theme.Text.onBrand }
        if restsOnDarkCap { return Theme.Keys.labelOnFunction }
        let resting = usesNeutralActionTint ? Theme.Keys.label : tint
        return resting.opacity(isDisabled ? KeyView.disabledLabelOpacity : 1)
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
