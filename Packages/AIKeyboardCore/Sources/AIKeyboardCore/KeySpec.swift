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
    /// bar, plus the three the layout editor adds.
    ///
    /// They are caps rather than special-cased views because the point of the
    /// editor is that a user can move them into the grid, and a grid key is a
    /// `KeySpec`. Drawing them here also means one implementation: a control
    /// cannot behave differently depending on which of the two places it was put.
    case emoji
    case quickTone
    case cursorLeft
    case cursorRight
    case hideKeyboard
    /// Reply and Fix, run straight from a key.
    ///
    /// **They exist because the action row made them destinations rather than menu
    /// items.** There used to be an `aiMenu` cap that opened a panel listing four
    /// actions, costing a tap to reach any of them; with a row of actions under the
    /// keys the two that need no further choice run outright, and the panel is
    /// deleted. Rewrite keeps needing one choice — a register — so it stays
    /// `quickTone`, which runs the default and holds the rest behind a long press.
    ///
    /// Fix is deliberately not folded into `quickTone`. `KeyboardController`
    /// `runDefaultTone` carries the reason the one-tap button is Rewrite and not
    /// Fix: `Prompts.fix` keeps the writer's register on purpose and `EditScope`
    /// undoes any change the model cannot name as a mistake, so a tone pointed at
    /// Fix would have nothing to do.
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
        case .dictation: return "Dictate"
        case .emoji: return "Emoji"
        case .quickTone: return "One-tap rewrite"
        case .cursorLeft: return "Cursor left"
        case .cursorRight: return "Cursor right"
        case .hideKeyboard: return "Hide keyboard"
        // The action's own title, so the key and the row label cannot drift.
        case .aiReply: return AIAction.reply.title
        case .aiFix: return AIAction.fix.title
        }
    }
}

/// How wide a key is, in multiples of the standard letter key.
public enum KeyWidth: Equatable, Sendable {
    case unit(CGFloat)
    /// Splits whatever is left over in the row between all keys marked flexible.
    case flexible
    /// A fixed width in points, the same on every plane and in all sixty-four
    /// languages. Shift, delete and the plane switch that brackets the third row.
    /// See `KeyboardLayout.widths(for:totalWidth:unitWidth:spacing:)`.
    case pinned
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

    public init(
        _ cap: KeyCap, width: KeyWidth = .unit(1), id: String? = nil, alternates: [String] = []
    ) {
        self.cap = cap
        self.width = width
        self.alternates = alternates
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
        case .character(let value): return "char-\(value)"
        case .shift: return "shift"
        case .backspace: return "backspace"
        case .plane(_, let label): return "plane-\(label)"
        case .globe: return "globe"
        case .settings: return "settings"
        case .space: return "space"
        case .ret: return "return"
        case .dictation: return "dictation"
        case .emoji: return "emoji"
        case .quickTone: return "quick-tone"
        case .cursorLeft: return "cursor-left"
        case .cursorRight: return "cursor-right"
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

    public init(id: Int, keys: [KeySpec], sideInsetUnits: CGFloat = 0) {
        self.id = id
        self.keys = keys
        self.sideInsetUnits = sideInsetUnits
    }
}
