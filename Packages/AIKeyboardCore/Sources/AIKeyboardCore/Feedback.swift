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

    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    private static let selection = UISelectionFeedbackGenerator()
    private static let notification = UINotificationFeedbackGenerator()

    /// Call before a burst of taps so the Taptic engine is warm and the first
    /// tap is not late.
    public static func prepare() {
        light.prepare()
        selection.prepare()
    }

    public static func keyPress() {
        guard hapticsEnabled else { return }
        light.impactOccurred(intensity: 0.6)
    }

    public static func modifierPress() {
        guard hapticsEnabled else { return }
        selection.selectionChanged()
    }

    public static func actionPress() {
        guard hapticsEnabled else { return }
        medium.impactOccurred()
    }

    public static func success() {
        guard hapticsEnabled else { return }
        notification.notificationOccurred(.success)
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
        case .shift, .plane, .globe, .settings, .dictation, .emoji, .quickTone,
            .cursorLeft, .cursorRight, .hideKeyboard, .aiReply, .aiFix:
            return .modifier
        }
    }
}
