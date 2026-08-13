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

    // MARK: Palette

    /// Which accent `Brand` currently answers with.
    ///
    /// **Cached rather than read from the store per access, and that is a
    /// latency decision.** `Brand.solid` is touched at 63 call sites, several of
    /// them inside `KeyView`'s per-key drawing, so a keyboard redraw would put
    /// thirty-odd `UserDefaults` lookups and string-to-enum parses on a path this
    /// repo measures in milliseconds. Refreshed instead at the three moments it
    /// can change: `SharedStore.load()` at each process launch,
    /// `SharedStore.brandPalette`'s `didSet` in the app, and
    /// `KeyboardViewController.viewWillAppear` in the extension — which is the
    /// cross-process one, since the picker runs in the app and iOS keeps a
    /// keyboard instance alive across it.
    ///
    /// Changing this does **not** repaint anything by itself. SwiftUI has no way
    /// to know a global moved, so the two roots invalidate explicitly — see the
    /// `.id(store.brandPalette)` in `RootView` and `OnboardingFlow`.
    public static var palette: BrandPalette = .orange

    // MARK: Brand

    /// One signature hue, held across the app and the keyboard.
    /// The gradient is same-hue and stays reserved for AI moments only: the
    /// sparkle key, the AI panel header, an active suggestion. Never for chrome.
    ///
    /// **Which hue is the user's choice now, and every name here is a computed
    /// property because of it.** `BrandPalette` is picked in onboarding and
    /// stored in the App Group; these read `Theme.palette`, so a call site that
    /// was written against a constant keeps working unchanged. Nothing else in
    /// `Theme` moves: a palette is the accent and only the accent.
    public enum Brand {
        public static var start: Color { Theme.palette.color(.fillStart) }
        public static var end: Color { Theme.palette.color(.fillEnd) }

        public static var gradient: LinearGradient {
            LinearGradient(
                colors: [start, end],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        public static var softGradient: LinearGradient {
            LinearGradient(
                colors: [start.opacity(0.14), end.opacity(0.14)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        /// Tint, icons, strokes, and accent text use the signature hue.
        ///
        /// **No longer always `start`, and monochrome is why.** In the three
        /// coloured palettes this is the same literal `start` resolves to, as it
        /// always was. In monochrome it is a *lighter* graphite than anything
        /// that gets filled, because this role sits on the app's own surfaces
        /// and the fill roles sit under white text, and grey cannot satisfy both
        /// floors with one value.
        public static var solid: Color { Theme.palette.color(.solid) }

        /// Filled surfaces that carry white text use the deeper end of the same
        /// gradient, and the split is a measured one rather than a preference.
        ///
        /// **White on `start` is 2.91:1, which is under WCAG's 3:1 floor for large
        /// text and well under the 4.5:1 for body.** The teal this palette
        /// replaced was 3.74:1, so the rebrand was a regression, not an
        /// inheritance. It reaches every primary button, the return key and the
        /// playground's message bubbles — every place `Text.onBrand` sits on a
        /// brand fill. `end` is 3.64:1, which clears large text, keeps the
        /// identity, and is a colour the palette already shipped as the far end of
        /// `gradient`.
        ///
        /// `solid` deliberately stays on `start`: tint, icons, strokes and accent
        /// text sit on the app's own light surfaces, where the bright orange is
        /// the more legible of the two and the one the design is built around.
        ///
        /// **That 3.64:1 is now the worst of the four palettes rather than the
        /// only one.** Pink's fill is 5.35:1 under white and blue's is 5.17:1, so
        /// both clear the 4.5:1 body floor the orange never did, and
        /// monochrome's is 13.34:1 in light and 4.80:1 in dark. The orange is
        /// unchanged on purpose — moving it would move the default every
        /// existing install is already wearing — so a user who wants the caption
        /// under a lit action key to clear AA can now get there by choosing a
        /// different palette, which is not what this row was for but is a real
        /// consequence of it.
        public static var action: Color { end }
    }

    // MARK: Semantic

    public enum Semantic {
        /// The only red in the product: recording and errors, nothing else.
        public static let record = Color(hex: 0xC84B47)
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
        public static let background = Color.adaptive(light: 0xE2E4E8, dark: 0x1E2122)
        public static let letter = Color.adaptive(light: 0xFFFEFA, dark: 0x54595B)
        public static let function = Color.adaptive(light: 0xADB3BE, dark: 0x2C2C2E)
        /// Deep graphite cap, used by the strongest function keys (shift, plane
        /// switch). White glyphs only — never put `Keys.label` text on it.
        public static let functionStrong = Color.adaptive(light: 0x2C3031, dark: 0x171A1B)
        /// Soft graphite cap for secondary controls (delete, emoji).
        public static let functionSoft = Color.adaptive(light: 0x626766, dark: 0x3A3F40)
        /// Label colour for glyphs sitting on `functionStrong` / `functionSoft`.
        public static let labelOnFunction = Color.adaptive(light: 0xFFFEFA, dark: 0xF4F3EF)
        /// Pressed state inverts: letters darken, function keys lighten.
        ///
        /// **A letter press has to clear the keyboard background, not merely the
        /// cap.** 0xE4E1DB sat on the same step as `background` (0xE2E4E8), so a
        /// tap vanished around the thumb. 0xD4D0C8 cleared it by 0.14 luma and
        /// still read as a tint. This is the original function-key grey's
        /// visibility kept in the letter caps' warm family, so a press is a grey
        /// key among white ones rather than a function key that wandered into
        /// the grid. Dark mode lifts the other way onto a light fill, which is
        /// why the glyph is `labelOnLetterPressed` rather than `label`.
        public static let letterPressed = Color.adaptive(light: 0xB8B2A8, dark: 0x989C9E)
        /// Graphite on `letterPressed`. Not `Keys.label`, which goes cream in
        /// dark — a pressed letter is a mid fill in both appearances.
        public static let labelOnLetterPressed = Color(hex: 0x2C3031)
        public static let functionPressed = Color.adaptive(light: 0xFFFEFA, dark: 0x54595B)
        public static let label = Color.adaptive(light: 0x2C3031, dark: 0xF4F3EF)
        public static let secondaryLabel = Color.adaptive(light: 0x626766, dark: 0xC7C7CC)
        public static let shadow = Color.adaptive(light: 0x898A8D, dark: 0x000000)
        /// The banner's pill. Not the emoji grid: that wears `background`, the
        /// same as the letters it replaced.
        ///
        /// **Raised by the same amount `background` was, because it is only ever
        /// read against it.** At 0xE6E8ED it sat 21 units above the old
        /// 0xD1D3D9; lightening the background alone would have left 4, and the
        /// banner's idle pill is this colour at half opacity — a 2-unit lift,
        /// which is a strip the user cannot see is a strip. This keeps it at the
        /// same fraction of the distance from `background` to a white key.
        public static let panel = Color.adaptive(light: 0xF4F3EF, dark: 0x242829)
        public static let card = Color.adaptive(light: 0xFFFEFA, dark: 0x2E3435)
    }

    // MARK: App surfaces

    public enum Surface {
        public static let background = Color.adaptive(light: 0xF4F3EF, dark: 0x1E2122)
        public static let raised = Color.adaptive(light: 0xFFFEFA, dark: 0x262B2C)
        public static let elevated = Color.adaptive(light: 0xFFFEFA, dark: 0x2E3435)
        public static let separator = Color.adaptive(light: 0xDEDFDA, dark: 0x3A4041)
    }

    public enum Text {
        public static let primary = Color.adaptive(light: 0x2C3031, dark: 0xF4F3EF)
        public static let secondary = Color.adaptive(light: 0x626766, dark: 0xA6AAA8)
        public static let tertiary = Color.adaptive(light: 0x9A9C98, dark: 0x7E8381)
        public static let onBrand = Color.white
    }

    // MARK: Type scale
    //
    // The only font sizes the app uses. Raw `.system(size:)` calls drift; name
    // the role instead. Keyboard chrome keeps its own sizes in `Glyph`.

    public enum Fonts {
        /// Screen-level hero line, used once per screen at most. The product's
        /// voice is SF Pro Display at heavy weights with tight tracking — the
        /// web hero uses the same stack at 800 / -.055em.
        public static let display = Font.system(size: 28, weight: .bold)
        /// Tab chrome titles (Home, Languages, Keys, Settings).
        public static let page = Font.system(size: 20, weight: .bold)
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
        public static let key: CGFloat = 8
        public static let chip: CGFloat = 12
        public static let card: CGFloat = 20
        public static let sheet: CGFloat = 28
        public static let pill: CGFloat = 999
    }

    // MARK: Depth
    //
    // The house shadow is a low, soft lift — felt rather than seen. Reserved
    // for heroes, sheets, and keycaps; rows and inline chrome stay flat so the
    // hierarchy reads.

    public enum Depth {
        public static let color = Color.black.opacity(0.08)
        public static let radius: CGFloat = 24
        public static let y: CGFloat = 12
    }

    // MARK: Motion

    public enum Motion {
        private static var reduce: Bool { UIAccessibility.isReduceMotionEnabled }

        /// Standard state change. Fast enough to feel instant, slow enough to be read.
        public static var quick: Animation {
            .easeOut(duration: reduce ? 0.08 : 0.18)
        }
        /// Finger-down on a key. Faster than `quick` so the press reads as a click.
        public static let press = Animation.easeOut(duration: 0.10)
        /// Panels sliding in and out over the key rows. A keyboard overlay, not a
        /// sheet: 0.22s, not the 0.34s this used to spend opening emoji.
        public static var panel: Animation {
            reduce
                ? .easeOut(duration: 0.12)
                : .spring(response: 0.22, dampingFraction: 0.92)
        }
        /// Content appearing inside a panel that is already open.
        public static var content: Animation {
            reduce
                ? .easeOut(duration: 0.12)
                : .spring(response: 0.28, dampingFraction: 0.9)
        }
        /// A language switch: the letter keys slide with the swipe. Longer than
        /// `quick` so the incoming layout can be read, still under 300ms so it
        /// never feels like waiting. Reduce Motion keeps the crossfade.
        public static var swipe: Animation {
            reduce
                ? .easeOut(duration: 0.12)
                : .spring(response: 0.30, dampingFraction: 0.90)
        }

        /// A balloon growing out of a key. Opacity alone under Reduce Motion.
        public static func pop(reduceMotion: Bool) -> AnyTransition {
            guard !reduceMotion else { return .opacity }
            return .asymmetric(
                insertion: .scale(scale: 0.6, anchor: .bottom).combined(with: .opacity),
                removal: .opacity
            )
        }
    }
}

public extension View {
    /// Applies the `Theme.Depth` ambient shadow. For cards and heroes; pair
    /// with a hairline border, never stacked on top of rows.
    func ambientDepth() -> some View {
        shadow(color: Theme.Depth.color, radius: Theme.Depth.radius, y: Theme.Depth.y)
    }
}
