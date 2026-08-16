import CoreGraphics
import Foundation

// MARK: - What a slot does

/// The job assigned to one editable key.
///
/// Each of these is something `KeyboardController` already does, which is why
/// the catalogue is this size and not larger: a keyboard that can be rearranged
/// into an action nothing implements is worse than one that cannot be
/// rearranged at all.
public enum SlotAction: Codable, Hashable, Sendable {
    case shift
    case backspace
    case numbersPlane
    case symbolsPlane
    case globe
    case settings
    case space
    case ret
    case dictation
    case emoji
    case copyclip
    case quickTone
    case cursorLeft
    case cursorRight
    case deleteForward
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
    /// look identical on the cap and quietly lose all of that. It is drawn on all
    /// three planes: the numbers plane carries the same five marks on the row
    /// above, and that is not a reason to move the one key a thumb finds without
    /// looking.
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
        case .settings: return "Settings"
        case .space: return "Space"
        case .ret: return "Return"
        case .dictation: return "Dictation"
        case .emoji: return "Emoji"
        case .copyclip: return "CopyClip"
        case .quickTone: return "One-tap rewrite"
        case .cursorLeft: return "Cursor left"
        case .cursorRight: return "Cursor right"
        case .deleteForward: return "Forward delete"
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
        .backspace, .ret, .shift, .numbersPlane, .symbolsPlane, .globe, .settings,
        .dictation, .emoji, .copyclip, .reply, .fix, .quickTone, .punctuation,
        .cursorLeft, .cursorRight, .deleteForward, .hideKeyboard,
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

    /// Half-unit steps, then fill once the drag clears the last step.
    public static func snapped(from rawUnits: CGFloat) -> SlotWidth {
        if rawUnits > maximumUnits + 0.35 { return .fill }
        return clampedUnits((rawUnits * 2).rounded() / 2)
    }

    /// Finger delta on a handle, in letter-key units.
    public static func proposed(
        start: SlotWidth, startPixels: CGFloat, translation: CGFloat, unit: CGFloat
    ) -> SlotWidth {
        let unit = max(unit, 1)
        let startUnits: CGFloat
        switch start {
        case .fill: startUnits = max(minimumUnits, startPixels / unit)
        case .units(let value): startUnits = value
        }
        return snapped(from: startUnits + translation / unit)
    }
}

// MARK: - One editable key

public struct SlotSpec: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var action: SlotAction
    public var width: SlotWidth

    /// Whether this key draws its name under its glyph — the user's answer, on
    /// the six keys that have a name to draw (`SlotAction.hasLabel`).
    ///
    /// **Nil is neither yes nor no: it is "whatever this key would do where it
    /// stands".** The shipped rule is a position and a width — the action row
    /// keeps Emoji and Dictate as bare glyphs, and no key narrower than
    /// `KeyView.captionMinimumWidth` names itself — and a layout stored by any
    /// earlier build has no opinion to record, because there was no switch to
    /// throw. Optional is also what makes that a migration rather than a
    /// decision: the synthesized `Codable` uses `decodeIfPresent`, so a missing
    /// key reads back as nil and an untouched layout re-encodes byte for byte.
    /// `KeySpec.showsActionCaption(inRow:width:)` is where the three answers meet.
    public var showsLabel: Bool?

    /// A fresh `UUID` by default, and that is load-bearing: identity cannot come
    /// from the action, because a user is allowed to put two commas on one row
    /// and two keys with one id is a `ForEach` with duplicate identity.
    public init(
        id: UUID = UUID(), action: SlotAction, width: SlotWidth = .units(1),
        showsLabel: Bool? = nil
    ) {
        self.id = id
        self.action = action
        self.width = width
        self.showsLabel = showsLabel
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

    /// A run of rows that share one key height.
    ///
    /// **Three bands, not one height and not one per row, and the middle is the
    /// interesting part.** The action row and the space row each do a job of
    /// their own, so each gets its own height: a thumb resting on space wants
    /// more than a thumb reaching for Rewrite, or less, and that is a real
    /// preference. The *letters* are deliberately one value for all of them,
    /// including the optional number row. They are a grid the eye reads as a
    /// block, a stagger inside it reads as a rendering bug rather than a choice,
    /// and `KeyboardLayout.rows` is extracted from Apple's own data for 64
    /// languages where the three rows are peers. `fittedKeyHeight` also squeezes
    /// the numbers plane's fourth row into the block the letters occupy, and
    /// that arithmetic has one letter height to divide or it has none.
    public enum RowBand: String, CaseIterable, Codable, Sendable {
        case letters
        case action
        case bottom

        public var title: String {
            switch self {
            case .letters: return "Letter keys"
            case .action: return "Action row"
            case .bottom: return "Bottom row"
            }
        }
    }

    /// The three letter rows and the optional number row.
    public var keyHeight: CGFloat
    /// `cursorRow`: CopyClip, Fix, settings, Rewrite, dictation.
    public var actionRowHeight: CGFloat
    /// The space row.
    public var bottomRowHeight: CGFloat
    public var rowSpacing: CGFloat
    public var reach: Reach

    /// **36pt is the floor, not `Theme.Metrics.minTouchTarget`'s 44.** The
    /// keyboard ships at 44 for the letters and **39 for the action row**, so a
    /// rail set at Apple's comfortable minimum would fire on the untouched
    /// default, and a rail that fires on the default is noise rather than a rail.
    /// The action row is the band that makes that concrete now rather than a
    /// hypothetical: it is 3pt off this floor by design.
    public static let keyHeightRange: ClosedRange<CGFloat> = 36...56
    public static let rowSpacingRange: ClosedRange<CGFloat> = 8...16

    /// Today's `Theme.Metrics` values, so the shipped default is a no-op.
    ///
    /// Spelled out rather than read from `Theme.Metrics`, so
    /// `testDefaultGeometryMatchesTheShippedMetrics` is comparing two numbers
    /// somebody had to keep in step rather than one number with itself. The
    /// action row is shorter than the letters on purpose; `Theme.Metrics
    /// .actionRowHeight` carries the arithmetic that keeps the total unmoved.
    public static let `default` = LayoutGeometry(
        keyHeight: 44, rowSpacing: 12, reach: .full, actionRowHeight: 39)

    public func height(_ band: RowBand) -> CGFloat {
        switch band {
        case .letters: return keyHeight
        case .action: return actionRowHeight
        case .bottom: return bottomRowHeight
        }
    }

    public mutating func setHeight(_ value: CGFloat, for band: RowBand) {
        switch band {
        case .letters: keyHeight = value
        case .action: actionRowHeight = value
        case .bottom: bottomRowHeight = value
        }
    }

    /// **The two row heights default to the letter height rather than to a
    /// constant**, so every existing call site — both presets, every test
    /// fixture — keeps describing a keyboard whose rows are all one height,
    /// which is what they meant when there was only one number to give.
    public init(
        keyHeight: CGFloat, rowSpacing: CGFloat, reach: Reach,
        actionRowHeight: CGFloat? = nil, bottomRowHeight: CGFloat? = nil
    ) {
        self.keyHeight = keyHeight
        self.actionRowHeight = actionRowHeight ?? keyHeight
        self.bottomRowHeight = bottomRowHeight ?? keyHeight
        self.rowSpacing = rowSpacing
        self.reach = reach
    }

    /// **Hand-written for the two new keys only, and the fallback is what makes
    /// it a migration.** A layout stored by any earlier build has one
    /// `keyHeight` and no row heights at all; decoding those as a constant would
    /// silently reshape a keyboard somebody had already tuned, and decoding them
    /// as required keys would throw and drop the layout back to the default. The
    /// missing key means "this row was the same as the letters", because that is
    /// the only keyboard the old model could describe. `encode(to:)` stays
    /// synthesized.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let base = try container.decode(CGFloat.self, forKey: .keyHeight)
        keyHeight = base
        actionRowHeight =
            try container.decodeIfPresent(CGFloat.self, forKey: .actionRowHeight) ?? base
        bottomRowHeight =
            try container.decodeIfPresent(CGFloat.self, forKey: .bottomRowHeight) ?? base
        rowSpacing = try container.decode(CGFloat.self, forKey: .rowSpacing)
        reach = try container.decode(Reach.self, forKey: .reach)
    }
}
