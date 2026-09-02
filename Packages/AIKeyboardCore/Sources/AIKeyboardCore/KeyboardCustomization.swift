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
    /// The leading end of the suggestion bar. Reply by default.
    public var barLeading: [SlotSpec]
    /// The trailing end. The minimise key by default.
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
    /// now one row above the keys, which is the row the user asked
    /// for and which the editor can rearrange like any other.
    ///
    /// Three consequences, all deliberate:
    ///
    /// - **`barLeading` is Reply. `barTrailing` is Hide keyboard.** The three
    ///   candidates stay the bar's job. Reply is the one AI action that does not
    ///   sit in the action row, so it can keep that row two-and-two around a
    ///   narrow centre key. The trailing end is the minimise key, which is the
    ///   one control on this keyboard that puts it away — iOS gives a third-party
    ///   keyboard no system dismiss, so without a key of our own a user in a
    ///   field with no Return has nothing to tap. **Neither end is editable any
    ///   more**: the layout editor's Suggestion bar section is gone, so these two
    ///   are what every user gets unless they pick a preset that writes its own.
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
        barLeading: [SlotSpec(action: .reply)],
        barTrailing: [SlotSpec(action: .hideKeyboard)],
        showsNumberRow: false,
        bottomRow: [
            SlotSpec(action: .numbersPlane, width: .units(1.3)),
            SlotSpec(action: .emoji, width: .units(1.0)),
            SlotSpec(action: .space, width: .fill),
            SlotSpec(action: .punctuation, width: .units(1.0)),
            SlotSpec(action: .ret, width: .units(KeyboardLayout.trailingFunctionKeyUnits))
        ],
        cursorRow: Self.actionRow
    )

    /// The action row as it ships, in one row above the keys.
    ///
    /// **Ordered so the destructive-looking one is furthest from the space bar.**
    /// Dictation is the only control here that starts something the user then has
    /// to stop, and it sits at the far end rather than next to the keys a thumb
    /// is already travelling between.
    ///
    /// CopyClip and Fix on the left, Rewrite and dictation on the right, the gear
    /// 1.0 units in the true middle. Four `.fill` keys share the leftover so the
    /// centre key stays narrow in all 64 languages.
    ///
    /// **Emoji and the gear have traded places twice, and this is the second
    /// trade: Emoji is back beside `123` and the gear holds the narrow centre.**
    /// The seats keep their own widths and their own cap colours, so both rows
    /// look exactly as they did either way round — see `KeyView.capKind`.
    ///
    /// **What the trade cost, and what paid for it.** While Emoji sat here it was
    /// the only way out of its own grid: a panel hid the letter *and bottom* rows
    /// and `showsActionRow` kept this one, so `KeyView.label` turning the Emoji
    /// key into `ABC` / `אבג` was the entire exit. Moving Emoji down into a row
    /// the grid covered would have stranded the user inside the grid. So the
    /// bottom row is drawn outside the panel's own stack now
    /// (`KeyboardView+Keys`), which is the iOS arrangement — `123` and `אבג` side
    /// by side under an open grid — and it costs the grid a row of emoji, four
    /// instead of five. `EmojiPanel.rowCount` carries that arithmetic and
    /// `testAnOpenEmojiGridAlwaysHasAWayBack` holds the invariant.
    ///
    /// **This array is read in landscape even though the row is not drawn there.**
    /// `Theme.Metrics.landscapeLayout(basedOn:)` empties `cursorRow` because
    /// there is no height for a second band, and `SuggestionBar.landscapeActions
    /// (for:)` then puts these controls in the suggestion bar. So the order here
    /// is the order a user sees in both orientations, and adding a control to
    /// this row adds it to the landscape bar as well.
    public static let actionRow: [SlotSpec] = [
        SlotSpec(action: .copyclip, width: .fill),
        SlotSpec(action: .fix, width: .fill),
        SlotSpec(action: .settings, width: .units(1.0)),
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
