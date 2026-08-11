import SwiftUI

extension KeyView {

    // MARK: Appearance

    /// Whether this key carries a cap of its own at rest.
    ///
    /// **Only the keys that insert something do.** Letters and the space bar are
    /// what a finger aims at a hundred times a message, and a drawn cap is what it
    /// aims at. Shift, delete, the plane switch, Settings, return and dictation are
    /// controls rather than targets, so they are drawn as bare glyphs on the
    /// keyboard's own surface. Their touch targets are unchanged — `KeyboardLayout`
    /// still gives them the same widths — but the boundary is no longer painted,
    /// which is why the press cap below is not decoration: with the resting cap
    /// gone it is the whole of the feedback that a control was hit.
    var hasRestingCap: Bool {
        switch spec.cap {
        case .character, .space: return true
        default: return false
        }
    }

    var showsCap: Bool { hasRestingCap || isPressed }

    var background: Color {
        guard hasRestingCap else {
            // Under a finger a control takes the *letter* cap, not the old
            // function grey. Grey on grey was legible as a press only because a
            // resting cap sat beside it to compare against; with nothing drawn at
            // rest the pressed state has to be the light one.
            if isPressed { return Theme.Keys.functionPressed }
            // Soft brand fill while this key's action is the one the banner is
            // reporting — same recipe as `SuggestionBar.edgeButton`'s active tint.
            if isActionActive { return Theme.Brand.solid.opacity(0.14) }
            return .clear
        }
        return isPressed ? Theme.Keys.letterPressed : Theme.Keys.letter
    }

    var accessibilityValue: String {
        guard spec.cap == .space else { return "" }
        guard let indication else {
            return enabledLanguages.count > 1 ? language.displayName : ""
        }
        return indication.isPending
            ? "Release for \(indication.language.displayName)"
            : indication.language.displayName
    }

    // MARK: Callouts

    /// The balloon that pops above a letter while the finger is down, so the
    /// glyph stays readable under the thumb.
    ///
    /// No `!showsAlternates` here: a key that has a popup never has a callout in
    /// the first place, so the two can no longer be up at once. See
    /// `showsCharacterCallout`.
    @ViewBuilder
    var callout: some View {
        if isPressed, showsCharacterCallout, case .character(let value) = spec.cap {
            Text(shift.isUppercase ? language.uppercased(value) : value)
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(Theme.Keys.label)
                .frame(width: width * 1.35, height: height * 1.05)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                        .fill(Theme.Keys.letter)
                        .shadow(color: Theme.Keys.shadow.opacity(0.35), radius: 4, y: 2)
                )
                .offset(y: -height - 4)
                .allowsHitTesting(false)
                .transition(.opacity)
        }
    }

    /// Only a key with nothing else to show.
    ///
    /// **A key that has a popup shows the popup and nothing before it.** The
    /// callout and the popup are two balloons in the same place drawing the same
    /// glyph, so a hold used to play as one appearing, a beat, then the other
    /// replacing it — most visible in Hebrew, where every one of the twenty-seven
    /// letters carries a geresh, so every letter did it. The popup already leads
    /// with the character the key typed (see `alternateItems`), which is the whole
    /// job the callout was doing; a hold that opens it therefore loses nothing,
    /// and `KeyView.alternatesDelay` is short enough that the gap before it reads
    /// as part of the press rather than as a dead moment.
    ///
    /// The punctuation key was the first key to work this way and is no longer a
    /// special case: it has alternates like the rest of them.
    var showsCharacterCallout: Bool { !hasAlternates }

    /// The same balloon, for the language a slide along the space bar is pointing
    /// at. Only while the finger is down: once it lifts the thumb is out of the
    /// way and the space bar's own caption is the confirmation.
    @ViewBuilder
    var languageCallout: some View {
        if let indication, indication.isPending {
            LanguageCallout(indication: indication)
                .offset(y: -height - 6)
                .allowsHitTesting(false)
                .transition(.opacity)
        }
    }
}
