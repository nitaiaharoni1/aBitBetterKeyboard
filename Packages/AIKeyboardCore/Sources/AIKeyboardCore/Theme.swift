import SwiftUI
import UIKit

// MARK: - Hex helpers

public extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

public extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(UIColor(hex: hex, alpha: alpha))
    }

    /// A color that resolves differently in light and dark appearance.
    static func adaptive(light: UInt32, dark: UInt32, alpha: Double = 1) -> Color {
        Color(
            UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(hex: dark, alpha: alpha)
                    : UIColor(hex: light, alpha: alpha)
            })
    }
}

// MARK: - Design tokens

/// Single source of truth for the visual language, shared by the app and the keyboard.
public enum Theme {

    // MARK: Brand

    /// The two ends of the signature gradient. Reserved for AI moments only:
    /// the sparkle key, the AI panel header, an active suggestion. Never for chrome.
    public enum Brand {
        public static let start = Color(hex: 0x2DD4BF)  // teal
        public static let end = Color(hex: 0x6366F1)  // indigo

        public static let gradient = LinearGradient(
            colors: [start, end],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        public static let softGradient = LinearGradient(
            colors: [start.opacity(0.18), end.opacity(0.18)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        /// Solid stand-in for the gradient where a single color is required.
        public static let solid = Color.adaptive(light: 0x4F46E5, dark: 0x8B8CF9)
    }

    // MARK: Semantic

    public enum Semantic {
        public static let record = Color(hex: 0xFF453A)
        public static let success = Color.adaptive(light: 0x0F9D58, dark: 0x30D158)
        public static let warning = Color.adaptive(light: 0xB45309, dark: 0xF59E0B)
    }

    // MARK: Keyboard surfaces
    //
    // Tuned against the system keyboard so ours reads as native, not as a
    // web page pasted over the bottom of the screen.

    public enum Keys {
        public static let background = Color.adaptive(light: 0xD1D3D9, dark: 0x161618)
        public static let letter = Color.adaptive(light: 0xFFFFFF, dark: 0x4E4E51)
        public static let function = Color.adaptive(light: 0xADB3BE, dark: 0x2C2C2E)
        /// Pressed state inverts: letters darken, function keys lighten.
        public static let letterPressed = Color.adaptive(light: 0xADB3BE, dark: 0x6C6C70)
        public static let functionPressed = Color.adaptive(light: 0xFFFFFF, dark: 0x4E4E51)
        public static let label = Color.adaptive(light: 0x000000, dark: 0xFFFFFF)
        public static let secondaryLabel = Color.adaptive(light: 0x3C3C43, dark: 0xC7C7CC)
        public static let shadow = Color.adaptive(light: 0x898A8D, dark: 0x000000)
        /// The panel that slides over the key rows (AI, emoji, dictation).
        public static let panel = Color.adaptive(light: 0xE6E8ED, dark: 0x1C1C1F)
        public static let card = Color.adaptive(light: 0xFFFFFF, dark: 0x2C2C31)
    }

    // MARK: App surfaces

    public enum Surface {
        public static let background = Color.adaptive(light: 0xF6F7F9, dark: 0x0B0B0F)
        public static let raised = Color.adaptive(light: 0xFFFFFF, dark: 0x17171C)
        public static let elevated = Color.adaptive(light: 0xFFFFFF, dark: 0x20202A)
        public static let separator = Color.adaptive(light: 0xE3E5EA, dark: 0x2A2A32)
    }

    public enum Text {
        public static let primary = Color.adaptive(light: 0x0B0B0F, dark: 0xF5F5F7)
        public static let secondary = Color.adaptive(light: 0x60636B, dark: 0x9C9CA6)
        public static let tertiary = Color.adaptive(light: 0x8E9198, dark: 0x6E6E78)
        public static let onBrand = Color.white
    }

    // MARK: Space & shape

    public enum Space {
        public static let xxs: CGFloat = 4
        public static let xs: CGFloat = 8
        public static let sm: CGFloat = 12
        public static let md: CGFloat = 16
        public static let lg: CGFloat = 20
        public static let xl: CGFloat = 24
        public static let xxl: CGFloat = 32
        public static let xxxl: CGFloat = 40
    }

    public enum Radius {
        public static let key: CGFloat = 5
        public static let chip: CGFloat = 10
        public static let card: CGFloat = 16
        public static let sheet: CGFloat = 24
        public static let pill: CGFloat = 999
    }

    // MARK: Motion

    public enum Motion {
        /// Standard state change. Fast enough to feel instant, slow enough to be read.
        public static let quick = Animation.easeOut(duration: 0.18)
        /// Panels sliding in and out over the key rows.
        public static let panel = Animation.spring(response: 0.34, dampingFraction: 0.86)
        /// Content appearing inside a panel that is already open.
        public static let content = Animation.spring(response: 0.28, dampingFraction: 0.9)
    }

    // MARK: Keyboard metrics
    //
    // Matched to the system keyboard on a standard-width iPhone in portrait.
    // Getting these wrong is the fastest way to make a custom keyboard feel cheap.

    public enum Metrics {
        public static let suggestionBarHeight: CGFloat = 46
        /// The live-capture row. Only occupies space while a session is running.
        public static let contextStripHeight: CGFloat = 30
        public static let keyHeight: CGFloat = 42
        public static let rowSpacing: CGFloat = 12
        public static let keySpacing: CGFloat = 6
        public static let sideInset: CGFloat = 3
        public static let topInset: CGFloat = 8
        public static let bottomInset: CGFloat = 4

        /// Height of the four key rows plus their insets.
        public static var keyAreaHeight: CGFloat {
            keyHeight * 4 + rowSpacing * 3 + topInset + bottomInset
        }

        /// Total height the keyboard extension asks the host app for. The strip
        /// is included only when a session is live, so the keyboard does not
        /// reserve space for a feature that is switched off.
        public static func totalHeight(withContextStrip: Bool = false) -> CGFloat {
            suggestionBarHeight + keyAreaHeight + (withContextStrip ? contextStripHeight : 0)
        }

        /// Apple's minimum comfortable target. Anything smaller gets mistapped.
        public static let minTouchTarget: CGFloat = 44
    }
}

// MARK: - Where our own keyboard is on the screen

/// How much of the screen our own keyboard covers, which is the one thing the
/// capture process cannot work out for itself.
///
/// It needs it because our own UI must not be part of the frame fingerprint.
/// `AIResultPanel.loading` repaints three shimmer lines at 60 Hz for the whole
/// five seconds of a read, and the keyboard is a third of the fingerprint band on
/// an iPhone 17 Pro, so with it left in the freshness gate retired the answer to
/// the very tap that paid for it. `CaptureIntent.ownUIHeightPermille` carries
/// this across; `FrameReduction.bottomCrop(ownUI:)` is what acts on it.
public enum KeyboardGeometry {

    /// iPhone 17 Pro in portrait: the device every number under
    /// `Bar/screen-context/` is measured on, and the fallback when there is no
    /// window to measure.
    public static let referenceScreenHeight: CGFloat = 874

    /// The bottom fraction of a `screenHeight`-tall screen our keyboard covers.
    ///
    /// **Always the tallest form, never the current one.** The context strip
    /// appears and disappears with the capture session, including in the middle
    /// of a read, and the crop it feeds decides the fingerprint's band: a band
    /// that moves mid-read retires the reading exactly as a conversation switch
    /// does, because the gate's only content condition is exact equality. Over-
    /// reporting by the height of the strip costs nothing — those rows are ours
    /// whether or not the strip is drawn in them.
    ///
    /// `gapBelow` is the strip of screen between the bottom of our view and the
    /// bottom edge of the display, where the system draws the home indicator over
    /// the keyboard. Only the runtime knows it, and it is bounded here rather
    /// than trusted: a bad measurement that grew the crop without limit would
    /// start removing the host's newest message from the fingerprint, which is
    /// the 23-of-29 failure the band measurement found.
    public static func ownUIHeightFraction(
        screenHeight: CGFloat, gapBelow: CGFloat = 0
    ) -> Double {
        guard screenHeight > 0 else { return 0 }
        let gap = min(max(0, gapBelow), Theme.Metrics.minTouchTarget)
        let covered = Theme.Metrics.totalHeight(withContextStrip: true) + gap
        return Double(min(covered, screenHeight) / screenHeight)
    }
}
