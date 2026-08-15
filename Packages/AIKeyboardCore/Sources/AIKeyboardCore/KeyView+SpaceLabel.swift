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
            enabledLanguages: enabledLanguages,
            height: height,
            dynamicTypeSize: dynamicTypeSize)
    }

    /// How much of the key's own height a scaled glyph may fill at the
    /// largest accessibility sizes.
    ///
    /// **The key does not grow with Dynamic Type — only the user's own choice
    /// in the layout editor does that (`LayoutGeometry.RowBand`) — so growth
    /// has to saturate short of the cap, or the glyph collides with the row
    /// above and below it.** The shipped default (43pt key, a 22-25pt glyph)
    /// sits at roughly half its height; 0.75 leaves real room to grow before
    /// it saturates and still clears the rounded corner at every height
    /// `LayoutGeometry.keyHeightRange` allows (36...56).
    static let characterHeightCeiling: CGFloat = 0.75

    /// Scales a key-cap glyph's base size for a Dynamic Type setting, capped
    /// so it never grows past the key that carries it, in either dimension.
    ///
    /// **A ceiling, not `minimumScaleFactor`.** `minimumScaleFactor` shrinks
    /// text back down to fit a box, which is the right tool when the length
    /// of the content is unknown — the punctuation key's two-line label and
    /// every action-key caption already carry one, for exactly that reason.
    /// A key cap is (almost always) one glyph of known size: capping the size
    /// it is *drawn* at, rather than drawing it large and shrinking it back,
    /// means the largest accessibility sizes see the most growth this key can
    /// hold, rather than a size that grew past the ceiling and was clamped
    /// back down — which is the opposite of what an AX5 user asked for.
    ///
    /// **`static`, and `dynamicTypeSize` is a parameter rather than another
    /// read of `self.dynamicTypeSize`**, so `KeyView.scaledGlyphSize(base:
    /// dynamicTypeSize:width:height:)` can be asked for two sizes against the
    /// identical key box without constructing two `KeyView`s inside two
    /// different SwiftUI environments — this test target renders nothing, and
    /// a bare `@Environment` read on a directly-constructed view only ever
    /// answers the default.
    static func scaledGlyphSize(
        base: CGFloat, dynamicTypeSize: DynamicTypeSize,
        width: CGFloat, height: CGFloat,
        widthFraction: CGFloat = 0.78, heightFraction: CGFloat = characterHeightCeiling
    ) -> CGFloat {
        let scaled = base * Theme.DynamicType.scale(for: dynamicTypeSize)
        // **The height ceiling must never fall below `base`.** The numbers and
        // symbols planes squeeze a fourth row into the letters plane's
        // three-row block (`Theme.Metrics.fittedKeyHeight`), which ships at
        // roughly 29pt against a 43pt letter key — well under `base *
        // heightFraction`. Without the floor, a digit key would render
        // *smaller* than it does today the moment this runs at the system
        // default (`.large`, where `scaled == base`). A row that is already
        // compressed for another reason simply does not grow with Dynamic
        // Type; it must not shrink because of it.
        let heightCeiling = max(base, height * heightFraction)
        return min(scaled, width * widthFraction, heightCeiling)
    }

    /// Instance convenience: this key's own box and the environment's current
    /// Dynamic Type setting.
    func scaledGlyphSize(
        base: CGFloat, widthFraction: CGFloat = 0.78,
        heightFraction: CGFloat = Self.characterHeightCeiling
    ) -> CGFloat {
        Self.scaledGlyphSize(
            base: base, dynamicTypeSize: dynamicTypeSize, width: width, height: height,
            widthFraction: widthFraction, heightFraction: heightFraction)
    }

    /// Scripts carry different amounts of ink, and a twelve-column layout has
    /// narrower keys than a ten-column one, so the size follows both — and
    /// now the user's own text-size setting, capped so the glyph never
    /// outgrows the key. See `scaledGlyphSize`.
    var characterFontSize: CGFloat {
        let base: CGFloat
        switch language.script {
        case .hebrew, .arabic, .thaana: base = 23
        // The scripts whose letters carry the most ink per glyph, so they need
        // the most room inside a key that is no wider.
        case .devanagari, .tamil, .georgian: base = 22
        case .latin, .cyrillic, .greek, .other: base = 25
        }
        return scaledGlyphSize(base: base)
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
    /// This key's own height, passed down rather than read again, so the two
    /// lines below can be capped the same way every other key-cap glyph is:
    /// growing with Dynamic Type without outgrowing the key.
    let height: CGFloat
    let dynamicTypeSize: DynamicTypeSize

    @Namespace private var strip
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var typeScale: CGFloat { Theme.DynamicType.scale(for: dynamicTypeSize) }
    /// The code strip (`EN`, `HE`) is a badge, the same tier as every other
    /// small label in this keyboard — capped at `Theme.Glyph.lightFloor`,
    /// the size this file already treats as the line between a caption and
    /// body text.
    private var codeFontSize: CGFloat { min(12 * typeScale, Theme.Glyph.lightFloor) }
    /// The language name when it is the key's *only* content (one language
    /// enabled, no code strip above it) is this key's primary label, so it
    /// gets real room: up to 40% of the key's own height.
    private var nameFontSize: CGFloat { min(15 * typeScale, height * 0.4) }
    /// The same name, smaller, when it is the confirmation line under the
    /// code strip rather than the key's only content — badge tier again.
    private var nameSecondaryFontSize: CGFloat { min(11 * typeScale, Theme.Glyph.lightFloor) }

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
                                .font(.system(size: codeFontSize, weight: code == lit ? .semibold : .regular))
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
                            size: codes.isEmpty ? nameFontSize : nameSecondaryFontSize,
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
