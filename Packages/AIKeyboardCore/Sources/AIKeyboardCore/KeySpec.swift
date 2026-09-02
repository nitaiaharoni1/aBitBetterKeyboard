import CoreGraphics
import Foundation

// MARK: - Key model

public enum KeyCap: Equatable, Sendable {
    case character(String)
    case shift
    case backspace
    /// Switches to another plane. The label is what the key shows now, not where it goes.
    case plane(KeyboardPlane, label: String)
    case globe
    case settings
    case space
    case ret
    case dictation
    /// The three controls that used to exist only as chrome in the suggestion
    /// bar, plus the four the layout editor adds.
    ///
    /// They are caps rather than special-cased views because the point of the
    /// editor is that a user can move them into the grid, and a grid key is a
    /// `KeySpec`. Drawing them here also means one implementation: a control
    /// cannot behave differently depending on which of the two places it was put.
    case emoji
    case copyclip
    case quickTone
    case cursorLeft
    case cursorRight
    case deleteForward
    case hideKeyboard
    /// Reply and Fix, run straight from a key.
    ///
    /// **They exist because the action row made them destinations rather than menu
    /// items.** Rewrite stays `quickTone`, which runs the default register and
    /// holds the rest behind a long press. Fix is deliberately not folded into
    /// that: a tone pointed at Fix would have nothing to do, because `Prompts.fix`
    /// keeps the writer's register and `EditScope` undoes any change the model
    /// cannot name as a mistake. Fix's own long press offers correction passes
    /// (`FixStyle`) instead — which mistakes count, not how the sentence sounds.
    case aiReply
    case aiFix

    public var isFunctionKey: Bool {
        switch self {
        case .character: return false
        case .space: return false
        default: return true
        }
    }

    public var accessibilityLabel: String {
        switch self {
        case .character(let value): return value
        case .shift: return "Shift"
        case .backspace: return "Delete"
        case .plane(_, let label): return label
        case .globe: return "Next keyboard"
        case .settings: return "Settings"
        case .space: return "Space"
        case .ret: return "Return"
        case .dictation: return "Record"
        case .emoji: return "Emoji"
        case .copyclip: return "CopyClip"
        case .quickTone: return "One-tap rewrite"
        case .cursorLeft: return "Cursor left"
        case .cursorRight: return "Cursor right"
        case .deleteForward: return "Forward delete"
        case .hideKeyboard: return "Hide keyboard"
        // The action's own title, so the key and the row label cannot drift.
        case .aiReply: return AIAction.reply.title
        case .aiFix: return AIAction.fix.title
        }
    }

    // In RTL the caret sits on the left of typed text, so backspace removes the
    // character to its right; the arrow must point at what it deletes. Rows stay
    // LTR; only the glyph flips.
    public static func backspaceSymbol(isRightToLeft: Bool) -> String {
        isRightToLeft ? "delete.right" : "delete.left"
    }

    public static func deleteForwardSymbol(isRightToLeft: Bool) -> String {
        isRightToLeft ? "delete.left" : "delete.right"
    }

    // `arrow.left` / `arrow.right` ARE in Apple's auto-mirroring list
    // (`legacy_flippable.plist`); `delete.left` is not. Key rows are pinned
    // `.leftToRight`, so we pick the name from `isRightToLeft` rather than
    // setting an RTL environment on the Image (that would also flip the cursor
    // arrows a second time, and would flip them in the editor by accident).
    public static func cursorLeftSymbol(isRightToLeft: Bool) -> String {
        isRightToLeft ? "arrow.right" : "arrow.left"
    }

    public static func cursorRightSymbol(isRightToLeft: Bool) -> String {
        isRightToLeft ? "arrow.left" : "arrow.right"
    }

    /// VoiceOver follows the glyph. Identifiers stay `cursor-left` / `cursor-right`.
    func accessibilityLabel(isRightToLeft: Bool) -> String {
        switch self {
        case .cursorLeft where isRightToLeft: return KeyCap.cursorRight.accessibilityLabel
        case .cursorRight where isRightToLeft: return KeyCap.cursorLeft.accessibilityLabel
        default: return accessibilityLabel
        }
    }
}

/// How wide a key is, in multiples of the standard letter key.
public enum KeyWidth: Equatable, Sendable {
    case unit(CGFloat)
    /// Splits whatever is left over in the row between all keys marked flexible.
    case flexible
    /// One of `count` equal parts of the whole row, gutters included:
    /// `(totalWidth - spacing * (count - 1)) / count`.
    ///
    /// The row is the basis, not this row's leftover after pinned keys, so a
    /// band key and a third-row letter key stamped with the same `count` draw
    /// the same width. `.unit` cannot: it ignores the gutter a merged key
    /// swallowed, so five two-unit keys came out one spacing short of the row.
    case slot(of: Int)
    /// The legacy fixed function-key width: 1.5 reference-column units, the same
    /// on every plane and in all sixty-four languages.
    /// See `KeyboardLayout.widths(for:totalWidth:unitWidth:spacing:)`.
    case pinned

    var isPinned: Bool {
        self == .pinned
    }
}

public struct KeySpec: Identifiable, Equatable, Sendable {
    public let id: String
    public let cap: KeyCap
    public let width: KeyWidth

    /// What a long press on this key offers instead.
    ///
    /// This is where every accent, hamza form and InScript shifted consonant
    /// lives. Without it a keyboard with three rows and no popup has to choose
    /// between an unfaithful layout and an unreachable letter: Apple's own
    /// Arabic layout has no key for أ, its Greek layout has no key for ά, and its
    /// Hindi layout puts half the consonants behind shift. Empty for most keys.
    public let alternates: [String]

    /// The letters a grouped cap carries, in the order the keyboard draws them.
    /// `nil` on every ordinary key.
    ///
    /// **Only the layout can say this, and both the drawing and the speaking need
    /// it.** `KeyCap` is a value: it holds the string `qw\nas` and cannot tell
    /// that from a `.com` snippet key, which is also a `.character` cap with
    /// several characters in it — and the two want opposite treatment. A snippet
    /// is a word: read it as one, draw it as one. A grouped cap is a picture of
    /// four keys: spell it to a screen reader, and draw its letters **one at a
    /// time**, or the Unicode bidi algorithm reverses every Hebrew cap. `קר` is an
    /// RTL run, so as a single string it draws ר to the left of ק while the
    /// keyboard underneath has ק on the left — the same mirroring that shipped six
    /// right-to-left layouts backwards once already, and one a row-order test
    /// cannot see because the row is right and the *cap* is reversed.
    public let groupedLetters: [String]?

    /// Whether the user asked for this key's name to be drawn under its glyph,
    /// or nil where they have not said. Only a key compiled from a `SlotSpec`
    /// can carry an answer; see `SlotSpec.showsLabel`.
    public let showsLabel: Bool?
    /// A layout-owned width refinement. Nil for every public `KeySpec`, which
    /// keeps `.pinned` at its original 1.5-unit meaning for package clients.
    let pinnedUnits: CGFloat?

    /// Whether this key draws its name under its glyph, in the row it is drawn
    /// in and at the width the solver gave it.
    ///
    /// **The stored answer wins over both halves of the shipped rule, the width
    /// floor included.** `KeyView.captionMinimumWidth` is a default — "a key
    /// wide enough to name itself should, and one that is not should not try" —
    /// and a default cannot be a rail against the one person it would fire on,
    /// who is standing in the layout editor watching this key while they throw
    /// the switch. A name squeezed onto a one-unit cap is visible in the canvas
    /// the moment it happens and is one tap from being undone. Same principle as
    /// the deleted `costsScreenContext` warning: do not report a choice back to
    /// the user as a problem a second after they made it on purpose.
    ///
    /// **The row is passed in rather than known**, because a `KeySpec` has no
    /// row: it is handed to `KeyView` by `KeyboardView+Keys`, which is the one
    /// place that has both.
    public func showsActionCaption(inRow rowID: Int, width: CGFloat) -> Bool {
        if let showsLabel { return showsLabel }
        // The shipped action row keeps Emoji and Dictate as glyphs — two names
        // people already know. CopyClip keeps its caption there, because the
        // clipboard mark is not one.
        let byPosition =
            rowID != KeyboardLayout.RowID.cursor || (cap != .emoji && cap != .dictation)
        return byPosition && width >= KeyView.captionMinimumWidth
    }

    /// What a screen reader should call this key: the letters, spelled.
    public var spokenLabel: String? {
        guard let letters = groupedLetters, letters.count > 1 else { return nil }
        return letters.joined(separator: " ")
    }

    /// The lines a grouped cap is drawn on, letters kept separate. Empty on an
    /// ordinary key.
    public var groupedLines: [[String]] {
        guard groupedLetters != nil, case .character(let value) = cap else { return [] }
        return value.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.map(String.init) }
    }

    public init(
        _ cap: KeyCap, width: KeyWidth = .unit(1), id: String? = nil, alternates: [String] = [],
        groupedLetters: [String]? = nil, showsLabel: Bool? = nil
    ) {
        self.cap = cap
        self.width = width
        self.alternates = alternates
        self.groupedLetters = groupedLetters
        self.showsLabel = showsLabel
        pinnedUnits = nil
        self.id = id ?? KeySpec.identifier(for: cap)
    }

    init(
        _ cap: KeyCap, width: KeyWidth, pinnedUnits: CGFloat, id: String? = nil,
        alternates: [String] = [], groupedLetters: [String]? = nil,
        showsLabel: Bool? = nil
    ) {
        self.cap = cap
        self.width = width
        self.alternates = alternates
        self.groupedLetters = groupedLetters
        self.showsLabel = showsLabel
        self.pinnedUnits = pinnedUnits
        self.id = id ?? KeySpec.identifier(for: cap)
    }

    /// The id without the uniquing suffix a compiled custom key carries.
    ///
    /// `char-,#a1b2c3d4` addresses as `char-,`. Every key that is not compiled
    /// from a `SlotSpec` has no suffix and answers itself. This is what
    /// `KeyView`'s accessibility identifier is built from, so `key-space` finds
    /// the space bar whether it came from `bottomRow` or from a custom layout.
    public var addressableID: String {
        id.split(separator: "#", maxSplits: 1).first.map(String.init) ?? id
    }

    private static func identifier(for cap: KeyCap) -> String {
        switch cap {
        // A grouped cap carries a line break between the rows it merged, and an
        // accessibility identifier with a newline in it is one a UI test cannot
        // type. `letters(inCap:)` drops the same character for the same reason:
        // it is layout, not content.
        case .character(let value):
            return "char-\(value.replacingOccurrences(of: "\n", with: "-"))"
        case .shift: return "shift"
        case .backspace: return "backspace"
        case .plane(_, let label): return "plane-\(label)"
        case .globe: return "globe"
        case .settings: return "settings"
        case .space: return "space"
        case .ret: return "return"
        case .dictation: return "dictation"
        case .emoji: return "emoji"
        case .copyclip: return "copyclip"
        case .quickTone: return "quick-tone"
        case .cursorLeft: return "cursor-left"
        case .cursorRight: return "cursor-right"
        case .deleteForward: return "delete-forward"
        case .hideKeyboard: return "hide-keyboard"
        // Kebab-case like their neighbours, because these reach a UI test and a
        // screen reader through `addressableID`: `key-ai-reply` is what a test
        // addresses, and it must not change once anything is written against it.
        case .aiReply: return "ai-reply"
        case .aiFix: return "ai-fix"
        }
    }
}

public struct KeyRow: Identifiable, Sendable {
    public let id: Int
    public let keys: [KeySpec]
    /// Extra inset on both sides, in units, for rows with fewer keys than the top row.
    public let sideInsetUnits: CGFloat

    /// How many key-heights tall this row is drawn, including the row spacing it
    /// swallows. One for every row that shipped first.
    ///
    /// **Two only for the grouped band**, which merges the two letter rows that
    /// stand clear of shift and delete into one row of double-height keys. It is
    /// a height *multiplier* rather than a point value so a row cannot invent
    /// space: two units is exactly the two rows it replaced plus the spacing that
    /// used to sit between them, which is why grouping does not change the
    /// keyboard's height. See `GroupedKeys.Row`.
    public let heightUnits: Int

    /// Points added to this row's drawn height, on top of `heightUnits`.
    ///
    /// **The numbers row and the space row are a pair, and they cancel.** Three
    /// points move off the digits (and off the matching top row of `#+=`) onto
    /// the space bar. Either bias alone would grow or shrink the keyboard; the
    /// two together leave the 368 pt fingerprint cliff where it is. Letter rows
    /// stay at zero. See `Theme.Metrics.rowHeightBias`.
    public let heightBias: CGFloat

    public init(
        id: Int, keys: [KeySpec], sideInsetUnits: CGFloat = 0, heightUnits: Int = 1,
        heightBias: CGFloat = 0
    ) {
        self.id = id
        self.keys = keys
        self.sideInsetUnits = sideInsetUnits
        self.heightUnits = max(1, heightUnits)
        self.heightBias = heightBias
    }

    /// How tall this row is drawn, given the layout's key height and row gap.
    ///
    /// `heightUnits` is the grouped-band multiplier; `heightBias` is the few
    /// points the numbers row gives the space row. Neither may change the
    /// keyboard's total: units replace the rows they swallowed, and the two
    /// biases cancel.
    public func drawnHeight(keyHeight: CGFloat, rowSpacing: CGFloat) -> CGFloat {
        keyHeight * CGFloat(heightUnits)
            + rowSpacing * CGFloat(max(0, heightUnits - 1))
            + heightBias
    }
}
