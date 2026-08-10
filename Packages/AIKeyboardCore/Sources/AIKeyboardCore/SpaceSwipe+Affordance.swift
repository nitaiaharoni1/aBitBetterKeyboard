import SwiftUI

extension SpaceSwipe {

    // MARK: What the space bar says before anyone touches it

    /// The language codes the space bar prints, in the order they are drawn, and
    /// which of them is lit — the first entry is leftmost, and `active` is the one
    /// shown lit.
    ///
    /// **The gesture had no affordance at all, and that is the defect this
    /// answers.** `KeyboardController.announceLanguage` names the language for
    /// 1.4s *after* a switch and `LanguageCallout` names it *during* a slide;
    /// both of those are feedback for somebody who already knows the gesture
    /// exists. A user who does not sees a key captioned "space" — "רווח" in
    /// Hebrew — and no reason to think it does anything but insert a space. The
    /// owner of the first device this shipped to had to be told.
    ///
    /// So at rest the key prints a strip of language codes above its ordinary
    /// caption, with the one in use lit, and `showsSlideAffordance` puts a chevron
    /// at each end of the key: the lit code says which language is on, the unlit
    /// ones say which others the gesture reaches, and the chevrons say the way to
    /// reach them. It is the shape SwiftKey ships. It costs no permanent room in
    /// the suggestion bar and it answers a question — "which language am I in?" —
    /// that nothing at rest answered.
    ///
    /// **The first version of this replaced the caption with the language name**,
    /// which named the language on but never the ones off, so the chevrons pointed
    /// at nothing the user could see. The strip names both, and the caption goes
    /// back to being the word for space.
    ///
    /// **Above three enabled languages the strip is a window rather than a list**,
    /// because a phone's space bar has room for about three codes and this keyboard
    /// offers sixty-four languages. The window is what a swipe left reaches, where
    /// you are, and what a swipe right reaches — so it stays an answer to "where
    /// does this gesture go", which a truncated list would not be. It wraps at both
    /// ends exactly as `language(from:in:places:)` does, because a strip that
    /// stopped at the edge would promise a dead end the gesture does not have.
    ///
    /// **With one language enabled there is nothing to slide to**, so the strip is
    /// empty and the chevrons go: an affordance for a gesture that cannot move is
    /// worse than none. `SpaceSwipe.places` already returns 0 for that case, so the
    /// two agree.
    public static func codeStrip(
        active: KeyboardLanguage, in enabled: [KeyboardLanguage]
    ) -> [KeyboardLanguage] {
        guard enabled.count > 1 else { return [] }
        guard enabled.count > 3 else { return enabled }
        // Not `?? 0`: a language that is not in the list has no neighbours to
        // show, and centring the window on the first entry would light a code the
        // user is not typing in.
        guard let centre = enabled.firstIndex(of: active) else { return Array(enabled.prefix(3)) }
        let count = enabled.count
        return [-1, 0, 1].map { enabled[((centre + $0) % count + count) % count] }
    }

    /// Whether the space bar shows the two chevrons that say it slides, and what
    /// VoiceOver is told instead of seeing them.
    public static func showsSlideAffordance(languageCount: Int) -> Bool { languageCount > 1 }

    public static func slideHint(languageCount: Int) -> String {
        showsSlideAffordance(languageCount: languageCount)
            ? "Slide left or right to change language" : ""
    }
}

// MARK: - What the space bar says

/// What the space bar is saying about the keyboard's language right now.
///
/// Two moments, and they need different things. **While the finger is down**
/// (`isPending`) the user has not committed yet and the thumb is covering the
/// space bar, so the name has to appear above it. **After it lands** the finger is
/// gone, the layout under it has already changed, and what is needed is a short
/// confirmation of what just happened — which is what the space bar itself says,
/// the way Gboard names the language it has just moved to.
public struct LanguageSwitchIndication: Equatable, Sendable {

    public let language: KeyboardLanguage

    /// Where `language` sits in the user's enabled list, and how long that list
    /// is. Drawn as dots rather than as thirteen names: at two languages it says
    /// which of the two, at fourteen it says how far along the list the slide has
    /// got and which way is further — and it is the same fixed-height row either
    /// way.
    public let position: Int
    public let count: Int

    /// True while the finger is still on the space bar and could still move on.
    public let isPending: Bool

    public init(language: KeyboardLanguage, position: Int, count: Int, isPending: Bool) {
        self.language = language
        self.position = position
        self.count = count
        self.isPending = isPending
    }
}

/// The balloon above the space bar naming the language a slide is pointing at.
///
/// Deliberately an overlay rather than a row of its own: it appears and
/// disappears mid-gesture, and a keyboard whose keys jump down a few points every
/// time a language is being chosen is worse than no indication at all. Same
/// treatment as `KeyView`'s letter callout and its long-press popup, for the same
/// reason.
struct LanguageCallout: View {

    let indication: LanguageSwitchIndication

    var body: some View {
        VStack(spacing: 4) {
            Text("\(indication.language.flag) \(indication.language.nativeName)")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.Keys.label)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            dots
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                .fill(Theme.Keys.letter)
                .shadow(color: Theme.Keys.shadow.opacity(0.35), radius: 5, y: 2)
        )
        // Position 0 is the leftmost dot whatever the keyboard's language,
        // because the gesture that moves through them is physical: sliding right
        // always moves right along this row. See `SpaceSwipe.language`.
        .environment(\.layoutDirection, .leftToRight)
    }

    private var dots: some View {
        HStack(spacing: 4) {
            ForEach(0..<max(1, indication.count), id: \.self) { index in
                Circle()
                    .fill(
                        index == indication.position
                            ? Theme.Brand.solid : Theme.Keys.secondaryLabel.opacity(0.3)
                    )
                    .frame(width: 5, height: 5)
            }
        }
    }
}
