import SwiftUI

extension KeyView {

    // MARK: Space bar

    /// The space bar: a strip of language codes over the word for space, with a
    /// chevron at each end of the key. `SpaceSwipe.codeStrip` carries why it is
    /// that rather than the single language name it used to be.
    ///
    /// **The chevrons are the only thing on this keyboard that says the gesture
    /// exists.** Naming the language after a switch and during a slide is
    /// feedback for somebody who already knows; a caption reading "space" is what
    /// somebody who does not sees, and they never find it. They are SF Symbols
    /// rather than the guillemets ‹ ›, which Unicode marks as mirrored characters
    /// and which therefore swap shape around a right-to-left name.
    ///
    /// They sit in a layer of their own, pushed to the key's two edges, rather than
    /// either side of the codes: the strip changes width as the codes under it
    /// change, and chevrons that hugged it would wander about the key on every
    /// switch. Everything is inside the key's own fixed frame, so nothing around it
    /// moves either, and pinned left to right because it is a control — the
    /// chevrons point at the two directions a finger can travel, and those do not
    /// swap when the language does. `SpaceSwipe.language` carries why.
    var spaceLabel: some View {
        SpaceBarLabel(
            language: language,
            indication: indication,
            enabledLanguages: enabledLanguages)
    }

    /// Scripts carry different amounts of ink, and a twelve-column layout has
    /// narrower keys than a ten-column one, so the size follows both.
    var characterFontSize: CGFloat {
        let base: CGFloat
        switch language.script {
        case .hebrew, .arabic, .thaana: base = 23
        // The scripts whose letters carry the most ink per glyph, so they need
        // the most room inside a key that is no wider.
        case .devanagari, .tamil, .georgian: base = 22
        case .latin, .cyrillic, .greek, .other: base = 25
        }
        return min(base, width * 0.78)
    }

    /// The same for a grouped cap, which carries several letters on one or two
    /// lines.
    ///
    /// **Bounded by the widest line and by the number of lines, not by the key's
    /// width alone.** A banded key is wider *and* taller than an ordinary one, so
    /// `characterFontSize`'s width rule alone would size the letters off the
    /// bottom of a two-line cap. The tracking between letters is paid for out of
    /// the same budget, which is what the 0.72 is: eight tenths of the key, less
    /// the gaps.
    ///
    /// **The widest line is at least two.** A one-letter line on an equal-width
    /// cap must not jump to a larger font than its two-letter neighbour, which is
    /// what made `ו` look like a different-sized button beside `קר`.
    func groupedFontSize(_ value: String) -> CGFloat {
        let lines = value.split(separator: "\n", omittingEmptySubsequences: false)
        let widest = CGFloat(max(2, lines.map(\.count).max() ?? 1))
        return min(
            characterFontSize,
            width * 0.72 / widest,
            height * 0.56 / CGFloat(max(1, lines.count)))
    }

    /// Spacing between letters on a grouped cap. Zero because each letter
    /// occupies an equal cell that fills the key; a clustered gap left one-letter
    /// caps looking skinny beside their neighbours.
    static let groupedLetterSpacing: CGFloat = 0
}

/// The space bar's own drawing, pulled out of `KeyView` so the sliding highlight
/// can own a `Namespace` without putting one on every key.
private struct SpaceBarLabel: View {

    let language: KeyboardLanguage
    let indication: LanguageSwitchIndication?
    let enabledLanguages: [KeyboardLanguage]

    @Namespace private var strip
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // The lit code follows the finger, so a slide walks the highlight along the
        // strip and — past three languages, where the strip is a window — scrolls
        // it. Nil until a finger is down, which is the resting state.
        let lit = indication?.language ?? language
        let codes = SpaceSwipe.codeStrip(active: lit, in: enabledLanguages)
        let step = indication?.step ?? 0
        return ZStack {
            if !codes.isEmpty {
                HStack(spacing: 0) {
                    slideChevron("chevron.compact.left", emphasized: step < 0)
                    Spacer(minLength: 0)
                    slideChevron("chevron.compact.right", emphasized: step > 0)
                }
            }
            VStack(spacing: 0) {
                if !codes.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(codes, id: \.self) { code in
                            Text(code.shortName)
                                .font(.system(size: 12, weight: code == lit ? .semibold : .regular))
                                .foregroundStyle(
                                    code == lit
                                        ? Theme.Keys.label
                                        : Theme.Keys.secondaryLabel.opacity(0.6)
                                )
                                .background(alignment: .center) {
                                    if code == lit, !reduceMotion {
                                        Capsule()
                                            .fill(Theme.Keys.label.opacity(0.10))
                                            .padding(.horizontal, -5)
                                            .padding(.vertical, -2)
                                            .matchedGeometryEffect(id: "space-lit", in: strip)
                                    }
                                }
                        }
                    }
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                }
                Text(indication?.language.nativeName ?? language.spaceLabel)
                    .font(
                        .system(
                            size: codes.isEmpty ? 15 : 11,
                            weight: indication == nil ? .light : .medium)
                    )
                    .foregroundStyle(
                        indication == nil ? Theme.Keys.secondaryLabel : Theme.Keys.label
                    )
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .contentTransition(.opacity)
            }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .environment(\.layoutDirection, .leftToRight)
    }

    func slideChevron(_ name: String, emphasized: Bool) -> some View {
        Image(systemName: name)
            // One step above the house weight, and deliberately. These sit at 0.55
            // opacity on a grey key: a light hairline at this size disappears
            // altogether, and they are the only thing that says the slide exists.
            // Bigger than they were now that they live at the key's edges rather
            // than tucked against the caption, which is where the room is.
            .font(Theme.Glyph.medium(15))
            .foregroundStyle(Theme.Keys.secondaryLabel.opacity(emphasized ? 0.95 : 0.55))
            .scaleEffect(emphasized && !reduceMotion ? 1.18 : 1)
    }
}
