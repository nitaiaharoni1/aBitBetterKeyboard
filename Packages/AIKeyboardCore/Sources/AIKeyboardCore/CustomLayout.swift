import CoreGraphics
import Foundation

// MARK: - What a slot does

/// The job assigned to one editable key.
///
/// Thirteen of these are things `KeyboardController` already did before this
/// feature existed, which is why the catalogue is this size and not larger: a
/// keyboard that can be rearranged into an action nothing implements is worse
/// than one that cannot be rearranged at all.
public enum SlotAction: Codable, Hashable, Sendable {
    case shift
    case backspace
    case numbersPlane
    case symbolsPlane
    case globe
    case space
    case ret
    case dictation
    case emoji
    case aiMenu
    case quickTone
    case cursorLeft
    case cursorRight
    case hideKeyboard
    /// The two AI actions that need no further choice once tapped, so they can be
    /// keys rather than rows in a menu. See `KeyCap.aiReply` for why Rewrite is
    /// not one of them and stays `quickTone`.
    case reply
    case fix
    /// The letters plane's punctuation key: the script's own full stop on the cap
    /// and its other four marks behind a long press.
    ///
    /// **Not `text(".")`, and the difference is four marks and a language.**
    /// `KeyboardLayout.punctuationKey(for:)` picks the mark the script actually
    /// writes and hangs the rest off it, and `KeyView` draws them in miniature by
    /// recognising `KeyboardLayout.punctuationKeyID`. A literal full stop would
    /// look identical on the cap and quietly lose all of that. It is also dropped
    /// on the numbers and symbols planes, where all five marks are already on the
    /// row above.
    case punctuation
    /// Any literal, from a comma to `.com` to a phrase the user typed in. One
    /// case rather than four features.
    case text(String)

    /// What the editor calls it.
    public var title: String {
        switch self {
        case .shift: return "Shift"
        case .backspace: return "Delete"
        case .numbersPlane: return "Numbers"
        case .symbolsPlane: return "Symbols"
        case .globe: return "Next keyboard"
        case .space: return "Space"
        case .ret: return "Return"
        case .dictation: return "Dictation"
        case .emoji: return "Emoji"
        case .aiMenu: return "AI actions"
        case .quickTone: return "One-tap rewrite"
        case .cursorLeft: return "Cursor left"
        case .cursorRight: return "Cursor right"
        case .hideKeyboard: return "Hide keyboard"
        case .reply: return AIAction.reply.title
        case .fix: return AIAction.fix.title
        case .punctuation: return "Punctuation"
        case .text(let value): return value.isEmpty ? "Text" : value
        }
    }

    /// Everything the editor's Add drawer offers, in the order it offers it.
    ///
    /// `.space` is absent on purpose: the validator requires exactly the one that
    /// is already there, and a second space bar is not a layout anybody wants.
    public static let catalogue: [SlotAction] = [
        .backspace, .ret, .shift, .numbersPlane, .symbolsPlane, .globe,
        .dictation, .emoji, .reply, .fix, .quickTone, .aiMenu, .punctuation,
        .cursorLeft, .cursorRight, .hideKeyboard,
        .text(","), .text("?"), .text("!"), .text("@"), .text(".com")
    ]
}

// MARK: - How wide

public enum SlotWidth: Codable, Hashable, Sendable {
    /// Multiples of the standard letter key. 1.0 to 3.0.
    case units(CGFloat)
    /// Takes what the fixed keys in the row left over, split with any other
    /// `fill`. Maps to `KeyWidth.flexible`.
    case fill

    /// **The range starts at one whole key, and that *is* the minimum-width
    /// rail** — there is no separate one, and an earlier version of this comment
    /// promised one that does not exist.
    ///
    /// A unit is exactly the width of a letter key, whatever the language's column
    /// count and whatever the device: `KeyboardLayout.unitWidth` derives both from
    /// the same screen. So the narrowest key the editor can produce is precisely
    /// as wide as the `q` above it, and no point-based check can add anything —
    /// a 32pt floor would fire on the stock letter rows of a small phone before it
    /// fired on anything a user built. The rail that does the work is
    /// `LayoutValidator.widthBudget`, which keeps the row as a whole inside the
    /// grid.
    public static let minimumUnits: CGFloat = 1.0
    public static let maximumUnits: CGFloat = 3.0

    /// Clamped on the way in, so a value decoded from another build cannot put a
    /// key off the side of the screen.
    public static func clampedUnits(_ value: CGFloat) -> SlotWidth {
        .units(min(maximumUnits, max(minimumUnits, value)))
    }
}

// MARK: - One editable key

public struct SlotSpec: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var action: SlotAction
    public var width: SlotWidth

    /// A fresh `UUID` by default, and that is load-bearing: identity cannot come
    /// from the action, because a user is allowed to put two commas on one row
    /// and two keys with one id is a `ForEach` with duplicate identity.
    public init(id: UUID = UUID(), action: SlotAction, width: SlotWidth = .units(1)) {
        self.id = id
        self.action = action
        self.width = width
    }
}

// MARK: - Geometry

/// Which side of the screen the grid hugs when it is narrowed for one hand.
public enum Reach: String, Codable, Hashable, Sendable {
    case full
    case left
    case right

    /// How much of the width the grid takes. The remainder is the strip the other
    /// thumb cannot reach and no longer has to.
    public var widthFraction: CGFloat { self == .full ? 1.0 : 0.88 }
}

public struct LayoutGeometry: Codable, Equatable, Sendable {
    public var keyHeight: CGFloat
    public var rowSpacing: CGFloat
    public var reach: Reach

    /// **36pt is the floor, not `Theme.Metrics.minTouchTarget`'s 44.** The
    /// keyboard already ships at 42, so a rail set at Apple's comfortable minimum
    /// would fire on the untouched default, and a rail that fires on the default
    /// is noise rather than a rail.
    public static let keyHeightRange: ClosedRange<CGFloat> = 36...56
    public static let rowSpacingRange: ClosedRange<CGFloat> = 8...16

    /// Today's `Theme.Metrics` values, so the shipped default is a no-op.
    public static let `default` = LayoutGeometry(keyHeight: 42, rowSpacing: 12, reach: .full)

    public init(keyHeight: CGFloat, rowSpacing: CGFloat, reach: Reach) {
        self.keyHeight = keyHeight
        self.rowSpacing = rowSpacing
        self.reach = reach
    }
}

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

// MARK: - Compiling one slot

public extension SlotAction {

    /// The cap this action draws as.
    ///
    /// Optional rather than non-optional so `testEveryCatalogueActionHasAKeyCap`
    /// can fail loudly if a case is ever added to the enum and forgotten here.
    /// Nothing returns nil today.
    func keyCap(language: KeyboardLanguage) -> KeyCap? {
        switch self {
        case .shift: return .shift
        case .backspace: return .backspace
        case .numbersPlane: return .plane(.numbers, label: "123")
        case .symbolsPlane: return .plane(.symbols, label: "#+=")
        case .globe: return .globe
        case .space: return .space
        case .ret: return .ret
        case .dictation: return .dictation
        case .emoji: return .emoji
        case .aiMenu: return .aiMenu
        case .quickTone: return .quickTone
        case .cursorLeft: return .cursorLeft
        case .cursorRight: return .cursorRight
        case .hideKeyboard: return .hideKeyboard
        case .reply: return .aiReply
        case .fix: return .aiFix
        // Its cap is the script's own mark, and the alternates that come with it
        // live on the `KeySpec` rather than the `KeyCap`, so the compiler builds
        // this one whole through `KeyboardLayout.punctuationKey(for:)`. Answered
        // here too, because callers that only want to know what it draws (the
        // editor's drawer, the bar) ask this.
        case .punctuation:
            return KeyboardLayout.punctuationKey(for: language).cap
        case .text(let value): return .character(value)
        }
    }

    /// The SF Symbol the editor's drawer draws beside the name. A `.text` action
    /// and the two plane keys draw their own characters instead, which is why
    /// this is optional.
    var glyph: String? {
        switch self {
        case .shift: return "shift"
        case .backspace: return "delete.left"
        case .numbersPlane, .symbolsPlane: return nil
        case .globe: return "globe"
        case .space: return "space"
        case .ret: return "return"
        case .dictation: return "mic"
        case .emoji: return "face.smiling"
        case .aiMenu: return "sparkles"
        case .quickTone: return AIAction.rewrite.icon
        // Each action's own icon, so the key, the row in `AIMenuPanel` and the
        // banner's label all draw one thing.
        case .reply: return AIAction.reply.icon
        case .fix: return AIAction.fix.icon
        case .cursorLeft: return "arrow.left"
        case .cursorRight: return "arrow.right"
        case .hideKeyboard: return "keyboard.chevron.compact.down"
        case .punctuation, .text: return nil
        }
    }
}
