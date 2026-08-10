import SwiftUI

extension KeyView {

    // MARK: Appearance

    /// Whether this key carries a cap of its own at rest.
    ///
    /// **Only the keys that insert something do.** Letters and the space bar are
    /// what a finger aims at a hundred times a message, and a drawn cap is what it
    /// aims at. Shift, delete, the plane switch, globe, return and dictation are
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
            return isPressed ? Theme.Keys.functionPressed : .clear
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
    @ViewBuilder
    var callout: some View {
        if isPressed, !showsAlternates, showsCharacterCallout, case .character(let value) = spec.cap {
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

    var showsCharacterCallout: Bool {
        spec.addressableID != KeyboardLayout.punctuationKeyID
    }

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
