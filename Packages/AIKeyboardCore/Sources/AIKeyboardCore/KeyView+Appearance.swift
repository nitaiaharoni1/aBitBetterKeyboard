import SwiftUI
import UIKit

extension KeyView {

    // MARK: Appearance

    /// The cap a key wears, by its role in the palette.
    ///
    /// **Every key carries a cap of its own at rest**, and the colour carries
    /// the role — warm white for letters, space and the AI actions, deep
    /// graphite for shift and the plane switch, soft graphite for the other
    /// controls, orange for return. The fill, the glyph's colour and the whole
    /// depth recipe below are all keyed off this one switch, so a cap can never
    /// take one role's colour with another role's shadow. `KeyStyleButton`
    /// takes the same enum for the same reason.
    enum CapKind {
        case letter, strong, soft, action, record
    }

    var capKind: CapKind {
        // **Record red outranks the brand cap, and it is the narrowest state on
        // this keyboard.** A recording used to announce itself in a 69pt strip
        // with a waveform running across it; with the strip gone, the key is the
        // whole of the notice, and "the microphone in your keyboard is on right
        // now" is not a sentence an orange cap identical to the one Fix wears can
        // carry. `Theme.Semantic.record` is the only red in the product and this
        // is what it is for. It is deliberately off through a pause and off while
        // the last words are transcribed — see `DictationKeyState`.
        if dictationState.isRecording { return .record }
        // **A running action wears the primary cap, whole.** It used to paint a 14%
        // brand wash over whatever cap the key already had, which on the warm-white
        // AI keys is a barely-there tint — on a phone, in daylight, beside four
        // identical white caps, the microphone's "I am recording right now" read as
        // a slightly pink key. Answering it here rather than in `background` is what
        // keeps the rule this switch was written for: the fill, the glyph's colour
        // and the depth recipe all come from one answer, so an orange cap can never
        // end up with a white cap's shadow or a white cap's graphite glyph.
        if isActionActive { return .action }
        switch spec.cap {
        // Warm white stays dominant: letters, space, and the AI actions, whose
        // accent is the glyph's tint rather than the cap.
        case .character, .space, .quickTone, .aiReply, .aiFix:
            return .letter
        // The strongest controls: shift and the plane switch.
        case .shift, .plane:
            return .strong
        // The main action.
        case .ret:
            return .action
        // Delete, emoji, dictation and the neutral controls.
        default:
            return .soft
        }
    }

    /// The cap worn at rest.
    var restingCap: Color {
        switch capKind {
        case .letter: return Theme.Keys.letter
        case .strong: return Theme.Keys.functionStrong
        case .action: return Theme.Brand.action
        case .record: return Theme.Semantic.record
        case .soft: return Theme.Keys.functionSoft
        }
    }

    /// Whether the resting cap is a dark graphite one, which is what decides the
    /// glyph: warm white on the graphite caps, graphite on everything light.
    var restsOnDarkCap: Bool { capKind == .strong || capKind == .soft }

    var background: Color {
        if isPressed {
            // **Keyed off `capKind`, not off the cap.** The two said the same thing
            // for every key that ships — the white-cap list below is exactly
            // `.letter` — until an active key started wearing the orange cap, at
            // which point a press on it would have darkened it like a letter
            // instead of lightening it like the return key it now matches.
            //
            // Every dark or orange cap lightens to the letter white under a finger,
            // the way stock iOS inverts its function keys; the white caps darken a
            // step, the letter-key inversion.
            return capKind == .letter ? Theme.Keys.letterPressed : Theme.Keys.functionPressed
        }
        return restingCap
    }

    /// The glyph's colour, resolved against the fill actually behind it.
    ///
    /// A pressed fill is light in every appearance, so its glyph is graphite
    /// whatever the resting cap was. At rest the dark caps take the warm-white
    /// `labelOnFunction`, and the orange caps — the return key, and whichever
    /// action is running — take `Text.onBrand`.
    var labelColor: Color {
        if isPressed { return Theme.Keys.label }
        if capKind == .action || capKind == .record { return Theme.Text.onBrand }
        return (restsOnDarkCap ? Theme.Keys.labelOnFunction : Theme.Keys.label)
            .opacity(isDisabled ? Self.disabledLabelOpacity : 1)
    }

    /// How far a key with nothing to do fades its glyph.
    ///
    /// The cap itself is left alone: it is still a key, in the row where the user
    /// left it, and fading the whole thing punches a hole in a grid whose evenness
    /// is most of how it reads. Dimming the label alone is what iOS does to a
    /// disabled filled button, and at 0.35 it is unmistakably off without becoming
    /// an empty cap somebody has to guess the name of.
    static let disabledLabelOpacity: Double = 0.35

    // MARK: Depth
    //
    // The keycap's physical read: a crisp 2pt contact line under it and a faint
    // ambient lift. Dark and orange caps carry the deeper contact lines. Both
    // are static so `KeyStyleButton` — the panel's key-styled controls — draws
    // identical material rather than a second opinion of it.

    /// The contact line: the hard shadow where the cap meets the keyboard.
    static func contactShadow(for kind: CapKind) -> Color {
        switch kind {
        case .letter: return .black.opacity(0.16)
        case .strong: return .black.opacity(0.45)
        case .soft: return .black.opacity(0.35)
        case .action: return Color(hex: 0xB95023, alpha: 0.55)
        case .record: return Color(hex: 0x8E2B28, alpha: 0.55)
        }
    }

    /// The ambient lift: soft, wide, and barely there.
    static func ambientShadow(for kind: CapKind) -> Color {
        switch kind {
        case .letter: return .black.opacity(0.06)
        case .strong: return .black.opacity(0.10)
        case .soft: return .black.opacity(0.08)
        case .action: return Theme.Brand.action.opacity(0.30)
        case .record: return Theme.Semantic.record.opacity(0.34)
        }
    }

    var accessibilityValue: String {
        // The microphone's state, which its label cannot carry: "Stop recording"
        // is what a tap does and says nothing about a countdown running out or a
        // recording sitting paused. See `DictationKeyState.accessibilityValue`.
        if spec.cap == .dictation { return dictationState.accessibilityValue }
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
