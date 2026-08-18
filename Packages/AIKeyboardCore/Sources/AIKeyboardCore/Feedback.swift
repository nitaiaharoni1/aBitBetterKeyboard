import UIKit
import AudioToolbox

/// Touch feedback. A keyboard that does not answer the thumb feels broken even
/// when it is functionally correct, so this is not decoration.
@MainActor
public enum Feedback {

    /// Asked at the press, never cached. Both switches live in the app and every
    /// call below runs in the keyboard extension, so a `Bool` filled once at
    /// launch is a setting that stops working for as long as iOS keeps that
    /// instance alive. See `SharedStore.storedKeySounds`.
    public static var hapticsEnabled: Bool { SharedStore.shared.storedHaptics }
    public static var soundEnabled: Bool { SharedStore.shared.storedKeySounds }

    /// How hard the user asked the presses to hit. Asked at the press for
    /// exactly the reason `hapticsEnabled` is: the dial is in the app and the
    /// press is in the extension.
    static var strength: HapticStrength { SharedStore.shared.storedHapticStrength }

    /// One collision for every press kind. `.light` at 0.6 was the mock;
    /// `.rigid` at 1.0 was a defined click that still read as a miss on device.
    /// `.heavy` at full intensity is the hardest impact UIKit will play, and it
    /// is what `HapticStrength.strong` — still the shipped default — plays.
    static let impactStyle = HapticStrength.default.style
    static let impactIntensity: CGFloat = 1.0

    static let keyPressStyle = impactStyle
    static let keyPressIntensity = impactIntensity
    static let modifierPressStyle = impactStyle
    static let actionPressStyle = impactStyle
    static let actionPressIntensity = impactIntensity

    /// Incremented by `playImpact` only. A `modifierPress` that went back to
    /// `selectionChanged()` would leave this still.
    static var impactCount = 0

    private static var impact = UIImpactFeedbackGenerator(style: impactStyle)
    private static var notification = UINotificationFeedbackGenerator()
    private static weak var attachedView: UIView?

    /// The style `impact` was actually built with.
    ///
    /// **A generator's style is fixed at init**, so moving the Strength dial
    /// means building a new generator — a setting that only changed the
    /// `intensity:` argument would keep playing the old collision damped, which
    /// is the effect this keyboard already rejected once. Recorded rather than
    /// recomputed so `retune` can rebuild on the press that follows the change
    /// and on no other: a generator rebuilt every press is a generator that is
    /// always cold, which is the "first tap is late" bug `attach` exists to fix.
    private(set) static var builtStyle = impactStyle

    /// Bind the generators to the keyboard's own view.
    ///
    /// A generator with no view is a free-floating motor. In a keyboard
    /// extension that is the usual reason the first taps are late or missing.
    /// iOS 17.5 is when UIKit grew the view-associated initialisers; below that
    /// this still warms the unbound pair. Same view twice only prepares: a new
    /// generator on every SwiftUI pass would go cold mid-burst.
    static func attach(to view: UIView) {
        if attachedView === view {
            prepare()
            return
        }
        if #available(iOS 17.5, *) {
            let style = strength.style
            impact = UIImpactFeedbackGenerator(style: style, view: view)
            notification = UINotificationFeedbackGenerator(view: view)
            builtStyle = style
        }
        attachedView = view
        prepare()
    }

    /// Rebuild the generator when, and only when, the user has moved the dial
    /// since the last press. Bound to the same view `attach` used, or the
    /// motor goes free-floating again and the first taps come back late.
    private static func retune(to style: UIImpactFeedbackGenerator.FeedbackStyle) {
        guard style != builtStyle else { return }
        if #available(iOS 17.5, *), let view = attachedView {
            impact = UIImpactFeedbackGenerator(style: style, view: view)
        } else {
            impact = UIImpactFeedbackGenerator(style: style)
        }
        builtStyle = style
        impact.prepare()
    }

    /// Call before a burst of taps so the Taptic engine is warm and the first
    /// tap is not late. Each play also prepares the next one.
    ///
    /// **Retunes first, because the dial is almost always moved while the
    /// keyboard is off screen.** Warming the generator the user just replaced
    /// leaves the rebuild to the first press, and a generator built at the press
    /// is a cold one — the late first tap this method exists to prevent.
    public static func prepare() {
        retune(to: strength.style)
        impact.prepare()
        notification.prepare()
    }

    public static func keyPress() { playImpact() }
    public static func modifierPress() { playImpact() }
    public static func actionPress() { playImpact() }

    /// **The Strength dial does not reach this one, and cannot.**
    /// `UINotificationFeedbackGenerator` has no style and no intensity — the
    /// three patterns are fixed by iOS, which is the point of them: a success
    /// buzz is a sentence, not a keypress. The switch still silences it.
    public static func success() {
        guard hapticsEnabled else { return }
        notification.notificationOccurred(.success)
        notification.prepare()
    }

    private static func playImpact() {
        guard hapticsEnabled else { return }
        retune(to: strength.style)
        impactCount += 1
        impact.impactOccurred(intensity: impactIntensity)
        impact.prepare()
    }

    /// The system key click. Only plays with Full Access; without it this is a
    /// silent no-op rather than an error, which is the behaviour we want.
    public static func keyClick(_ click: KeyClick = .tock) {
        guard soundEnabled else { return }
        AudioServicesPlaySystemSound(click.rawValue)
    }
}

/// How hard a press hits, as the user set it in Keys › Feel.
///
/// **The dial moves the collision, not a volume, and that is a measured choice
/// rather than a preference.** `impactOccurred(intensity:)` fades one waveform
/// down, and this keyboard already shipped that: `.light` damped to 0.6 made
/// every letter read as a *missed* key rather than as a gentle one. UIKit's
/// three impact styles are three different collisions, each played here at full
/// intensity, so the lightest setting is still a definite answer to the thumb.
///
/// Raw values start at 1 for the reason `GroupedKeys.Level`'s do: `integer(forKey:)`
/// answers 0 for a key that was never written, so 0 must not be a real case or an
/// untouched install reads as an explicit choice.
public enum HapticStrength: Int, CaseIterable, Sendable {
    case light = 1
    case medium = 2
    /// What every build before the dial existed played, and still the default.
    case strong = 3

    /// The shipped answer. Strongest, because a keyboard that under-answers the
    /// thumb reads as broken, and the user who wants less can now say so.
    public static let `default`: HapticStrength = .strong

    public var title: String {
        switch self {
        case .light: return "Light"
        case .medium: return "Medium"
        case .strong: return "Strong"
        }
    }

    var style: UIImpactFeedbackGenerator.FeedbackStyle {
        switch self {
        case .light: return .light
        case .medium: return .medium
        case .strong: return .heavy
        }
    }
}

/// The three sounds iOS ships for a keyboard.
///
/// They are the whole set: playing anything else means bundling an audio file,
/// and none of the three has a volume this keyboard can set. Declared outside
/// `Feedback` so `KeyCap.clickSound` below can answer without being dragged onto
/// the main actor.
public enum KeyClick: SystemSoundID {
    /// A letter, a digit, space, return — anything that puts text in.
    case tock = 1104
    /// Backspace, including every repeat while it is held down.
    case delete = 1155
    /// Shift, the plane switch, globe, and every other key that changes what the
    /// keyboard is rather than what the document says.
    case modifier = 1156
}

extension KeyCap {

    /// What this key sounds like.
    ///
    /// **Not optional, and the `switch` is exhaustive, and both are the point.**
    /// Every key on the system keyboard answers audibly; this one played `tock`
    /// for letters, space and return and nothing at all for backspace, shift, the
    /// plane switch, the cursor keys and the whole action row — a key that draws,
    /// animates and makes no sound reads as a key that missed the tap. `KeyCap`
    /// has associated values so it cannot be `CaseIterable` and no test can walk
    /// it; listing every case here instead means a cap added later fails the
    /// build until somebody chooses its sound, which is the guarantee a
    /// hand-written test list cannot give. `KeyClickTests` pins the mapping.
    public var clickSound: KeyClick {
        switch self {
        case .character, .space, .ret:
            return .tock
        case .backspace, .deleteForward:
            return .delete
        case .shift, .plane, .globe, .settings, .dictation, .emoji, .copyclip, .quickTone,
            .cursorLeft, .cursorRight, .hideKeyboard, .aiReply, .aiFix:
            return .modifier
        }
    }
}
