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

    /// One signature hue, deep teal, held across the app and the keyboard. The
    /// gradient is same-hue and stays reserved for AI moments only: the sparkle
    /// key, the AI panel header, an active suggestion. Never for chrome.
    public enum Brand {
        public static let start = Color(hex: 0x0D9488)  // teal
        public static let end = Color(hex: 0x0F766E)  // deep teal

        public static let gradient = LinearGradient(
            colors: [start, end],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        public static let softGradient = LinearGradient(
            colors: [start.opacity(0.14), end.opacity(0.14)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        /// Tint, icons, strokes, and accent text sitting on a page background.
        /// Brightens in dark mode so small glyphs stay legible.
        public static let solid = Color.adaptive(light: 0x0F766E, dark: 0x2DD4BF)

        /// Fills that carry `Text.onBrand` copy. Stays deep in dark mode so
        /// white button text keeps its contrast.
        public static let action = Color(hex: 0x0F766E)
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
        /// **Matched to the system's own keyboard colour, and that is what makes
        /// the shelf above us disappear.** iOS draws roughly 15 pt of its own
        /// chrome above the extension's view — rounded at the top, the same
        /// surface as the dock that holds the globe and the dictation mic below —
        /// and nothing in this process can paint, shrink or recolour it: the
        /// hosting view is pinned to all four edges of a `view` that is height
        /// constrained to `Metrics.totalHeight`. At the old 0xD1D3D9 that shelf
        /// read as an empty grey band sitting on top of the keyboard, because it
        /// was about 8% lighter than we were. Stock iOS paints its keyboard
        /// 0xE2E4E8 — measured off `Bar/layouts/stock/en_US.png` — so adopting it
        /// leaves no seam to see. Moving this moves the band back.
        public static let background = Color.adaptive(light: 0xE2E4E8, dark: 0x161618)
        public static let letter = Color.adaptive(light: 0xFFFFFF, dark: 0x4E4E51)
        public static let function = Color.adaptive(light: 0xADB3BE, dark: 0x2C2C2E)
        /// Pressed state inverts: letters darken, function keys lighten.
        public static let letterPressed = Color.adaptive(light: 0xADB3BE, dark: 0x6C6C70)
        public static let functionPressed = Color.adaptive(light: 0xFFFFFF, dark: 0x4E4E51)
        public static let label = Color.adaptive(light: 0x000000, dark: 0xFFFFFF)
        public static let secondaryLabel = Color.adaptive(light: 0x3C3C43, dark: 0xC7C7CC)
        public static let shadow = Color.adaptive(light: 0x898A8D, dark: 0x000000)
        /// The panel that slides over the key rows (AI, emoji, dictation), and the
        /// banner's pill.
        ///
        /// **Raised by the same amount `background` was, because it is only ever
        /// read against it.** At 0xE6E8ED it sat 21 units above the old
        /// 0xD1D3D9; lightening the background alone would have left 4, and the
        /// banner's idle pill is this colour at half opacity — a 2-unit lift,
        /// which is a strip the user cannot see is a strip. This keeps it at the
        /// same fraction of the distance from `background` to a white key.
        public static let panel = Color.adaptive(light: 0xEFF1F5, dark: 0x1C1C1F)
        public static let card = Color.adaptive(light: 0xFFFFFF, dark: 0x2C2C31)
    }

    // MARK: App surfaces

    public enum Surface {
        public static let background = Color.adaptive(light: 0xF4F6F6, dark: 0x0B0D0D)
        public static let raised = Color.adaptive(light: 0xFFFFFF, dark: 0x151A1A)
        public static let elevated = Color.adaptive(light: 0xFFFFFF, dark: 0x1F2626)
        public static let separator = Color.adaptive(light: 0xE1E6E5, dark: 0x283030)
    }

    public enum Text {
        public static let primary = Color.adaptive(light: 0x0D1414, dark: 0xF2F5F4)
        public static let secondary = Color.adaptive(light: 0x59625F, dark: 0x9AA4A1)
        public static let tertiary = Color.adaptive(light: 0x89918F, dark: 0x6C7572)
        public static let onBrand = Color.white
    }

    // MARK: Type scale
    //
    // The only font sizes the app uses. Raw `.system(size:)` calls drift; name
    // the role instead. Keyboard chrome keeps its own sizes in `Glyph`.

    public enum Fonts {
        /// Screen-level hero line, used once per screen at most.
        public static let display = Font.system(size: 28, weight: .bold)
        /// Card and section titles.
        public static let title = Font.system(size: 20, weight: .semibold)
        /// Row titles, button labels, emphasized body.
        public static let headline = Font.system(size: 17, weight: .semibold)
        /// Default reading text.
        public static let body = Font.system(size: 15)
        /// Secondary body, subtitles.
        public static let callout = Font.system(size: 14)
        /// Supporting detail, timestamps, footers.
        public static let caption = Font.system(size: 13)
        /// Uppercase section labels and compact badges.
        public static let micro = Font.system(size: 12, weight: .medium)
    }

    // MARK: Glyphs
    //
    // Every icon on the keyboard is drawn through here, so the monoline weight is
    // decided once rather than re-typed at sixty call sites and drifting.

    public enum Glyph {

        /// Below this, a light stroke stops being thin and starts being broken:
        /// the hairline falls under a device pixel at Display Zoom and the glyph
        /// smears into the key behind it. Badges and captions live under it.
        static let lightFloor: CGFloat = 13

        /// The house icon weight. Light above the floor, regular below it, so a
        /// caller never has to remember which side of the line a size is on.
        public static func font(_ size: CGFloat) -> Font {
            .system(size: size, weight: size >= lightFloor ? .light : .regular)
        }

        /// One step heavier, for a glyph that has to hold its own against text
        /// beside it — a header's back chevron, a row's leading mark.
        public static func medium(_ size: CGFloat) -> Font {
            .system(size: size, weight: size >= lightFloor ? .regular : .medium)
        }
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
}
