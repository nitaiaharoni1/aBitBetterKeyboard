import CoreGraphics
import Foundation

// MARK: - The whole customization

/// The shape of the keyboard, as the user described it.
///
/// **Letters are deliberately absent.** The three letter rows are extracted data
/// — 64 languages read out of Apple's own layout tables and held to
/// `Bar/layouts/` by `LayoutProvenanceTests` and `RenderedRowOrderTests` — so
/// they are not a thing anybody gets to rearrange. What is here is everything
/// that is not a letter, which is also the part that is genuinely
/// language-independent, which is what makes one stored value correct for all 64
/// rather than 64 stored values.
public struct KeyboardCustomization: Codable, Equatable, Sendable {
    /// The preset this exactly is, or nil once the user has edited it.
    public var preset: String?
    /// What Reset goes back to. Survives editing, which `preset` does not.
    public var basedOn: String
    public var geometry: LayoutGeometry
    /// The leading end of the suggestion bar.
    public var barLeading: [SlotSpec]
    /// The trailing end. Two controls by default: one-tap tone, then the sparkle.
    public var barTrailing: [SlotSpec]
    public var showsNumberRow: Bool
    public var bottomRow: [SlotSpec]
    /// Empty means the row is off. There is no separate flag, because a row with
    /// no keys and a row that is switched off are the same keyboard.
    public var cursorRow: [SlotSpec]

    public init(
        preset: String?,
        basedOn: String,
        geometry: LayoutGeometry,
        barLeading: [SlotSpec],
        barTrailing: [SlotSpec],
        showsNumberRow: Bool,
        bottomRow: [SlotSpec],
        cursorRow: [SlotSpec]
    ) {
        self.preset = preset
        self.basedOn = basedOn
        self.geometry = geometry
        self.barLeading = barLeading
        self.barTrailing = barTrailing
        self.showsNumberRow = showsNumberRow
        self.bottomRow = bottomRow
        self.cursorRow = cursorRow
    }

    /// What ships.
    ///
    /// **The five AI controls used to be scattered across three places, and every
    /// one of those places was the wrong size for them.** Emoji, the one-tap
    /// rewrite and the sparkle were 44pt chrome squeezed against the three
    /// candidates a user reads mid-word; dictation was a 1-unit glyph in the
    /// bottom row between space and the full stop; and Reply and Fix were not
    /// reachable at all without opening a panel that covered the keys. They are
    /// now one row of five under the keyboard, which is the row the user asked
    /// for and which the editor can rearrange like any other.
    ///
    /// Three consequences, all deliberate:
    ///
    /// - **`barLeading` and `barTrailing` are empty.** Not deleted —
    ///   `SuggestionBar` still draws whatever is put there and its separators are
    ///   already conditional on the arrays being non-empty — so a user who wants
    ///   the sparkle back at the end of the bar can put it back. The default is
    ///   three candidates edge to edge, which is what the bar is for.
    /// - **Dictation leaves the bottom row.** It would otherwise be on the
    ///   keyboard twice, and `LayoutValidator` would not say so: it warns about a
    ///   duplicate action *within* a row, and these would be in two. The unit it
    ///   gives up goes to the space bar, which is `.fill`.
    /// - **The action row is `cursorRow`.** There is no second row concept and no
    ///   second height path: `rowCount` already counts it, `Theme.Metrics
    ///   .keyAreaHeight(for:)` already measures it, and `KeyboardViewController`
    ///   already republishes its height when the customization changes. An empty
    ///   array is still the row switched off.
    ///
    /// Every width in `bottomRow` is copied from `KeyboardLayout.bottomRow`.
    /// `testTheDefaultCompilesToTodaysRows` is what holds all of this true rather
    /// than this comment.
    public static let `default` = KeyboardCustomization(
        preset: "default",
        basedOn: "default",
        geometry: .default,
        barLeading: [],
        barTrailing: [],
        showsNumberRow: false,
        bottomRow: [
            SlotSpec(action: .numbersPlane, width: .units(1.3)),
            SlotSpec(action: .globe, width: .units(1.0)),
            SlotSpec(action: .space, width: .fill),
            SlotSpec(action: .punctuation, width: .units(1.0)),
            SlotSpec(action: .ret, width: .units(2.2))
        ],
        cursorRow: Self.actionRow
    )

    /// The action row as it ships: everything the keyboard can do to the text,
    /// in one row under the keys.
    ///
    /// **Ordered so the destructive-looking one is furthest from the space bar.**
    /// Dictation is the only control here that starts something the user then has
    /// to stop, and it sits at the far end rather than next to the keys a thumb
    /// is already travelling between.
    ///
    /// Every slot is `.fill`, so the five split the width evenly and stay even in
    /// all 64 languages — a row of fixed units would have to be checked against
    /// `KeyboardLayout.columns(for:plane:)` for each of them, which is the
    /// Bulgarian overrun `LayoutValidator` exists to catch.
    public static let actionRow: [SlotSpec] = [
        SlotSpec(action: .emoji, width: .fill),
        SlotSpec(action: .reply, width: .fill),
        SlotSpec(action: .fix, width: .fill),
        SlotSpec(action: .quickTone, width: .fill),
        SlotSpec(action: .dictation, width: .fill)
    ]

    /// How many rows the key grid draws.
    ///
    /// The one number `Theme.Metrics.keyAreaHeight` used to hardcode as 4, which
    /// was right for exactly as long as the grid could only be three letter rows
    /// and a bottom row.
    public var rowCount: Int {
        3 + 1 + (showsNumberRow ? 1 : 0) + (cursorRow.isEmpty ? 0 : 1)
    }
}
