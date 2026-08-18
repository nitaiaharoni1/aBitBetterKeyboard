import Foundation

/// Which skin tone the emoji grid draws the 304 tonable emoji in.
///
/// **One setting for the whole grid, not one per emoji.** iOS remembers a tone
/// per emoji; this remembers one and paints every hand, every face and every
/// couple with it. The difference is what the user has to do to get a keyboard
/// that looks like them: one long press here against three hundred there. It is
/// also what makes the setting legible — a grid that is half toned and half not
/// has no state a user could describe, and no way back to plain short of
/// re-holding every cell they ever picked from.
///
/// **`generic` rather than `none` or `default`.** `.none` in an optional
/// position is `Optional.none` and Swift says nothing about it — this repo has
/// been bitten four times, and `EmojiSkinTone?` is exactly the shape that bites
/// (see `AGENTS.md`). `default` needs backticks everywhere it is written. The
/// case is the emoji as Unicode draws it with no modifier, which is what
/// "generic" already means in the standard's own wording.
///
/// The raw values are positions and are persisted, so they may not be
/// renumbered: 1...5 index `EmojiCatalog.variants(for:)` past its first entry,
/// in the light-to-dark order the generator wrote them.
public enum EmojiSkinTone: Int, CaseIterable, Sendable, Equatable {
    case generic = 0
    case light
    case mediumLight
    case medium
    case mediumDark
    case dark

    /// What VoiceOver calls it, appended to the emoji's own name.
    public var accessibilityName: String {
        switch self {
        case .generic: return "no skin tone"
        case .light: return "light skin tone"
        case .mediumLight: return "medium-light skin tone"
        case .medium: return "medium skin tone"
        case .mediumDark: return "medium-dark skin tone"
        case .dark: return "dark skin tone"
        }
    }

    /// A stored number this build does not know is not a reason to lose the
    /// keyboard's tone — it is a reason to draw the plain emoji, which is what
    /// every install starts at anyway.
    public static func stored(_ raw: Int) -> EmojiSkinTone {
        EmojiSkinTone(rawValue: raw) ?? .generic
    }
}
