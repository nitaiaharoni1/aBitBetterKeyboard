import SwiftUI

/// The accent the product wears, chosen by the user during onboarding.
///
/// **This is the whole of what a palette changes.** `Theme.Brand` is the single
/// accent in the product — every other colour (key caps, card surfaces, text)
/// is the same warm graphite set in every palette, and `Theme.Keys.background`
/// in particular is pinned to stock iOS's own keyboard grey so the shelf above
/// the extension has no seam to show. So a palette reaches the primary buttons,
/// the onboarding progress bar, the eyebrow labels, the AI moments, the lit
/// action key and the return key, and nothing else.
///
/// **Three roles rather than two, because monochrome needs them apart.** The
/// shipped orange used one hue for both jobs — `solid` for tint, icons, strokes
/// and accent text sitting on the app's own light surfaces, and `action` for
/// filled surfaces carrying `Theme.Text.onBrand` white — and got away with it
/// because a mid-orange is legible in both roles. Grey is not: the graphite that
/// reads as an accent on a dark background (0xA6AAA8, 6.90:1 against
/// `Surface.background` dark) is 2.35:1 under white text, which is a button
/// nobody can read. `solid` is measured against the surface behind it,
/// `fillStart`/`fillEnd` are measured against the white on top of them, and only
/// the second pair is ever filled.
public enum BrandPalette: String, CaseIterable, Sendable {
    /// The shipped default, unchanged, so an existing install does not wake up a
    /// different colour.
    case orange
    case pink
    case blue
    case monochrome

    public var title: String {
        switch self {
        case .orange: return "Orange"
        case .pink: return "Pink"
        case .blue: return "Blue"
        case .monochrome: return "Monochrome"
        }
    }

    public var subtitle: String {
        switch self {
        case .orange: return "The signature warm orange"
        case .pink: return "Brighter, and the loudest of the four"
        case .blue: return "Cool and closest to the system"
        case .monochrome: return "No colour at all, graphite only"
        }
    }

    // MARK: Roles

    /// Which of the three jobs a brand colour is doing. Named rather than passed
    /// as a keypath so the `UIColor` provider below captures something trivially
    /// `Sendable`.
    public enum Role: Sendable {
        /// Tint, icons, strokes and accent text, always on an app surface.
        /// Measured against `Theme.Surface.background`.
        case solid
        /// The light end of the AI gradient. Carries white text.
        case fillStart
        /// Filled surfaces carrying `Theme.Text.onBrand`. Carries white text and
        /// has to stay visible as a shape against the background behind it.
        case fillEnd
    }

    /// The literal for a role in one appearance.
    ///
    /// Only `monochrome` differs between light and dark. The three coloured
    /// palettes are one hex each in both, exactly as the shipped orange has
    /// always been, because a mid-saturation hue clears its floors on both
    /// backgrounds and an adaptive pair would be two numbers to keep true
    /// instead of one.
    ///
    /// Every number here was measured, not picked. Against white:
    /// orange's `fillEnd` is 3.64:1 (large text only — a known, documented
    /// compromise this change deliberately does not touch), pink's is 5.35:1 and
    /// blue's is 5.17:1, so both new colours clear the 4.5:1 body floor the
    /// orange never did. Against `Surface.background`, every `fillEnd` clears
    /// the 3:1 non-text floor a button's own edge needs: 4.46 / 3.03 / 3.14 in
    /// dark, and 3.27 / 4.82 / 4.65 in light.
    func hex(_ role: Role, dark: Bool) -> UInt32 {
        switch self {
        case .orange:
            switch role {
            case .solid, .fillStart: return 0xEE7442
            case .fillEnd: return 0xD9632F
            }
        case .pink:
            switch role {
            case .solid, .fillStart: return 0xE8589B
            case .fillEnd: return 0xC42A73
            }
        case .blue:
            switch role {
            case .solid, .fillStart: return 0x4A8CF7
            case .fillEnd: return 0x2563EB
            }
        case .monochrome:
            // The one palette that has to be adaptive, and the numbers are why.
            // A light-mode graphite (0x4A5051) is 7.40:1 against the light
            // surface and 1.97:1 against the dark one — invisible. The dark-mode
            // fills are then floored from *both* sides at once: light enough to
            // clear 3:1 against `Surface.background` dark (0x6E7375 is 3.37) and
            // dark enough to keep white text over 4.5:1 (0x6E7375 is 4.80). That
            // window is roughly 0x6E7375 to 0x7A7F81 wide and nothing outside it
            // satisfies both.
            switch role {
            case .solid: return dark ? 0xA6AAA8 : 0x4A5051
            case .fillStart: return dark ? 0x7A7F81 : 0x3F4445
            case .fillEnd: return dark ? 0x6E7375 : 0x2C3031
            }
        }
    }

    /// This palette's colour for a role, light and dark resolved the way every
    /// other adaptive token in `Theme` resolves them.
    ///
    /// An instance method rather than a static one, because the picker draws all
    /// four at once: each swatch shows its *own* palette while the rest of the
    /// screen wears the chosen one. `Theme.Brand` is the caller that asks the
    /// current palette; everything else names the palette it means.
    ///
    /// **A `UITraitCollection` trait was built here first and abandoned
    /// unverified — it is not known to be broken.** `UITraitDefinition` plus a
    /// `UITraitBridgedEnvironmentKey` is the documented way to give `UIColor` a
    /// dynamic provider that follows a custom value, and it would have removed
    /// the two `.id()` invalidations this design needs. It looked like it had
    /// failed, and the test that said so was the broken half: **a host-side
    /// `defaults write` into the App Group plist never reaches a simulator app,**
    /// because the simulator's `cfprefsd` answers from a cache that a shutdown,
    /// a cold boot and a `launchctl kickstart` all failed to drop. The app went
    /// on reading `orange` off a file that said `blue`, which looks exactly like
    /// a colour mechanism that does not work. The static below was then measured
    /// the way that actually works — force the value in `load()`, rebuild, and
    /// look — so it is the verified one, not the better one. If the `.id()`
    /// rebuild ever becomes a problem, the trait is worth retrying, with that
    /// same forcing trick rather than a plist edit.
    public func color(_ role: Role) -> Color {
        .adaptive(light: hex(role, dark: false), dark: hex(role, dark: true))
    }

    /// The AI gradient in this palette. Same construction as
    /// `Theme.Brand.gradient`, which is the one the product actually draws;
    /// this exists so the picker can show a palette that is not the current one.
    public var gradient: LinearGradient {
        LinearGradient(
            colors: [color(.fillStart), color(.fillEnd)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
