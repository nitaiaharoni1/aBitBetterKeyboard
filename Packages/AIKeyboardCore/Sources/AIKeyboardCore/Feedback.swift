import UIKit
import AudioToolbox

/// Touch feedback. A keyboard that does not answer the thumb feels broken even
/// when it is functionally correct, so this is not decoration.
@MainActor
public enum Feedback {

    public static var hapticsEnabled = true
    public static var soundEnabled = true

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
    public static func keyClick() {
        guard soundEnabled else { return }
        AudioServicesPlaySystemSound(1104)
    }
}
