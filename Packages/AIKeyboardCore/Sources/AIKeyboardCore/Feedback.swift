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

    /// One collision for every press kind. `.light` at 0.6 was the mock;
    /// `.rigid` at 1.0 was a defined click that still read as a miss on device.
    /// `.heavy` at full intensity is the hardest impact UIKit will play.
    static let impactStyle: UIImpactFeedbackGenerator.FeedbackStyle = .heavy
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
            impact = UIImpactFeedbackGenerator(style: impactStyle, view: view)
            notification = UINotificationFeedbackGenerator(view: view)
        }
        attachedView = view
        prepare()
    }

    /// Call before a burst of taps so the Taptic engine is warm and the first
    /// tap is not late. Each play also prepares the next one.
    public static func prepare() {
        impact.prepare()
        notification.prepare()
    }

    public static func keyPress() { playImpact() }
    public static func modifierPress() { playImpact() }
    public static func actionPress() { playImpact() }

    public static func success() {
        guard hapticsEnabled else { return }
        notification.notificationOccurred(.success)
        notification.prepare()
    }

    private static func playImpact() {
        guard hapticsEnabled else { return }
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
