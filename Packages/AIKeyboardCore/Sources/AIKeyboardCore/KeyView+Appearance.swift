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
        // is what it is for. It stays red through the second the last words
        // are transcribed, so the key does not flash orange record and invite
        // another tap — see `DictationKeyState`.
        if dictationState.isRecording { return .record }
        // **The microphone is the one key that wears a filled cap at rest**, and
        // it is orange so that turning red means something. Every other control
        // here is neutral until it is doing something; this one is the way into a
        // feature people do not think to look for, and a graphite key with a
        // waveform on it reads as another arrow or another mode switch. Orange to
        // red is then one property changing on a cap the eye already knows,
        // rather than a key appearing out of the background.
        if spec.cap == .dictation { return .action }
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

    /// How far a pressed cap seats, and how the two shadows collapse with it.
    /// Shared with `KeyStyleButton` so the emoji panel's key-styled controls
    /// cannot drift from the keys.
    static let pressTravel: CGFloat = 2
    static let restContactY: CGFloat = 2
    static let pressContactY: CGFloat = 0
    static let restAmbientRadius: CGFloat = 7
    static let pressAmbientRadius: CGFloat = 2
    static let restAmbientY: CGFloat = 4
    static let pressAmbientY: CGFloat = 1

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
        // The microphone's state, which its label cannot carry: "Pause recording"
        // is what a tap does and says nothing about a countdown running out. See
        // `DictationKeyState.accessibilityValue`.
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

    /// How tall the neck that meets the key is, and how far it sits into the cap
    /// so the balloon reads as growing out of it rather than hovering.
    static let calloutNeckHeight: CGFloat = 12
    static let calloutOverlap: CGFloat = 3

    /// The circle the glyph sits in: wider than the key, or it is not a preview.
    var calloutBubbleSize: CGFloat { max(width * 1.65, height * 1.35, 52) }

    /// Heavier and larger than the cap, so the letter is readable under a thumb.
    var calloutFontSize: CGFloat {
        max(characterFontSize * 1.4, min(34, calloutBubbleSize * 0.58))
    }

    private var calloutNeckWidth: CGFloat {
        min(width * 0.58, calloutBubbleSize * 0.38)
    }

    /// The balloon that pops above a letter while the finger is down, so the
    /// glyph stays readable under the thumb.
    ///
    /// Grows out of the key rather than fading in: a fade is a caption appearing,
    /// a scale from the bottom is the key itself lifting so the letter can be
    /// read. Reduce Motion keeps the fade. The popup takes this seat the moment
    /// it opens — `drawsCharacterCallout(popupIsVisible:)` is what keeps the two
    /// from stacking.
    @ViewBuilder
    var callout: some View {
        if isPressed, showsCharacterCallout, case .character(let value) = spec.cap {
            let glyph = shift.isUppercase ? language.uppercased(value) : value
            Text(displayLabel(glyph))
                .font(.system(size: calloutFontSize, weight: .medium))
                .foregroundStyle(Theme.Keys.label)
                .frame(width: calloutBubbleSize, height: calloutBubbleSize)
                .frame(
                    width: calloutBubbleSize,
                    height: calloutBubbleSize + Self.calloutNeckHeight,
                    alignment: .top
                )
                .background {
                    CharacterCalloutShape(neckWidth: calloutNeckWidth)
                        .fill(Theme.Keys.letter)
                        .shadow(color: Theme.Keys.shadow.opacity(0.35), radius: 4, y: 2)
                }
                .fixedSize()
                .offset(y: -height + Self.calloutOverlap)
                .allowsHitTesting(false)
                .transition(Theme.Motion.pop(reduceMotion: reduceMotion))
        }
    }

    /// Whether this key draws the press balloon *right now*.
    ///
    /// Reads `showsAlternates`, so a hold that has opened the strip no longer
    /// has a callout underneath it. Tests that cannot set that flag go through
    /// `drawsCharacterCallout(popupIsVisible:)` instead.
    var showsCharacterCallout: Bool { drawsCharacterCallout(popupIsVisible: showsAlternates) }

    /// **Letters preview on finger-down, including the ones that have a popup.**
    /// Hebrew's every letter carries a geresh, so gating this on `hasAlternates`
    /// left the whole alphabet with no tap feedback — a thumb covering the glyph
    /// and nothing above it. The balloon and the strip still cannot be up at
    /// once: pass `popupIsVisible: true` and this is false.
    ///
    /// The punctuation key still skips it. Its cap already wears the four marks,
    /// and previewing a lone period for the hold delay is the two-step open that
    /// was pulled. A grouped cap is several letters; a single balloon would name
    /// the wrong thing.
    func drawsCharacterCallout(popupIsVisible: Bool) -> Bool {
        guard case .character = spec.cap else { return false }
        guard spec.addressableID != KeyboardLayout.punctuationKeyID else { return false }
        guard spec.groupedLetters == nil else { return false }
        return !popupIsVisible
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
                .transition(
                    SpaceSwipe.calloutTransition(
                        step: indication.step, reduceMotion: reduceMotion))
        }
    }
}

/// The press balloon: a circle for the glyph, tapering down to the key.
///
/// One path rather than a circle stacked on a triangle, so the contact shadow
/// is a single silhouette. The neck starts inside the circle so the fill does
/// not leave a seam where they meet.
struct CharacterCalloutShape: Shape {
    var neckWidth: CGFloat

    func path(in rect: CGRect) -> Path {
        let neckHeight = min(KeyView.calloutNeckHeight, rect.height * 0.28)
        let diameter = min(rect.width, rect.height - neckHeight)
        let radius = diameter / 2
        let center = CGPoint(x: rect.midX, y: radius)
        let neckTop = diameter * 0.62
        let neckTopWidth = min(diameter * 0.46, max(neckWidth, 1) * 1.35)

        var path = Path()
        path.addEllipse(
            in: CGRect(
                x: center.x - radius, y: center.y - radius,
                width: diameter, height: diameter))

        var neck = Path()
        neck.move(to: CGPoint(x: center.x - neckTopWidth / 2, y: neckTop))
        neck.addLine(to: CGPoint(x: center.x + neckTopWidth / 2, y: neckTop))
        neck.addQuadCurve(
            to: CGPoint(x: center.x + neckWidth / 2, y: rect.maxY),
            control: CGPoint(x: center.x + neckWidth / 2, y: diameter + neckHeight * 0.15))
        neck.addLine(to: CGPoint(x: center.x - neckWidth / 2, y: rect.maxY))
        neck.addQuadCurve(
            to: CGPoint(x: center.x - neckTopWidth / 2, y: neckTop),
            control: CGPoint(x: center.x - neckWidth / 2, y: diameter + neckHeight * 0.15))
        path.addPath(neck)
        return path
    }
}
