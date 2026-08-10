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
        // The lit code follows the finger, so a slide walks the highlight along the
        // strip and — past three languages, where the strip is a window — scrolls
        // it. Nil until a finger is down, which is the resting state.
        let lit = indication?.language ?? language
        let codes = SpaceSwipe.codeStrip(active: lit, in: enabledLanguages)
        return ZStack {
            if !codes.isEmpty {
                HStack(spacing: 0) {
                    slideChevron("chevron.compact.left")
                    Spacer(minLength: 0)
                    slideChevron("chevron.compact.right")
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
                                        : Theme.Keys.secondaryLabel.opacity(0.6))
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
            }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .environment(\.layoutDirection, .leftToRight)
    }

    func slideChevron(_ name: String) -> some View {
        Image(systemName: name)
            // One step above the house weight, and deliberately. These sit at 0.55
            // opacity on a grey key: a light hairline at this size disappears
            // altogether, and they are the only thing that says the slide exists.
            // Bigger than they were now that they live at the key's edges rather
            // than tucked against the caption, which is where the room is.
            .font(Theme.Glyph.medium(15))
            .foregroundStyle(Theme.Keys.secondaryLabel.opacity(0.55))
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
}
