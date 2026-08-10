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
        case .space: return "Space"
        case .ret: return "Return"
        case .dictation: return "Dictation"
        case .emoji: return "Emoji"
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
        .dictation, .emoji, .reply, .fix, .quickTone, .punctuation,
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
