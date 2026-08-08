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
    case space
    case ret
    case dictation

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
        case .space: return "Space"
        case .ret: return "Return"
        case .dictation: return "Dictate"
        }
    }
}

/// How wide a key is, in multiples of the standard letter key.
public enum KeyWidth: Equatable, Sendable {
    case unit(CGFloat)
    /// Splits whatever is left over in the row between all keys marked flexible.
    case flexible
    /// Shift and delete share the space the letters do not use, the way iOS does it.
    case remainderShare
}

public struct KeySpec: Identifiable, Equatable, Sendable {
    public let id: String
    public let cap: KeyCap
    public let width: KeyWidth

    public init(_ cap: KeyCap, width: KeyWidth = .unit(1), id: String? = nil) {
        self.cap = cap
        self.width = width
        self.id = id ?? KeySpec.identifier(for: cap)
    }

    private static func identifier(for cap: KeyCap) -> String {
        switch cap {
        case .character(let value): return "char-\(value)"
        case .shift: return "shift"
        case .backspace: return "backspace"
        case .plane(_, let label): return "plane-\(label)"
        case .globe: return "globe"
        case .space: return "space"
        case .ret: return "return"
        case .dictation: return "dictation"
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

// MARK: - Layouts

public enum KeyboardLayout {

    /// The rows for a language and plane. Row 4 is appended by `bottomRow`.
    public static func rows(for language: KeyboardLanguage, plane: KeyboardPlane) -> [KeyRow] {
        switch plane {
        case .letters:
            return language == .hebrew ? hebrewLetters() : englishLetters()
        case .numbers:
            return numbers(for: language)
        case .symbols:
            return symbols(for: language)
        }
    }

    // MARK: Letters

    private static func englishLetters() -> [KeyRow] {
        [
            KeyRow(id: 0, keys: chars("qwertyuiop")),
            KeyRow(id: 1, keys: chars("asdfghjkl"), sideInsetUnits: 0.5),
            KeyRow(
                id: 2,
                keys: [KeySpec(.shift, width: .remainderShare)]
                    + chars("zxcvbnm")
                    + [KeySpec(.backspace, width: .remainderShare)]
            )
        ]
    }

    /// Hebrew is 22 letters plus 5 final forms across 8 / 10 / 9 keys, and it has
    /// no case, so there is no shift key. Delete sits at the leading edge, which
    /// mirrors to the left of the screen under right-to-left layout.
    private static func hebrewLetters() -> [KeyRow] {
        [
            KeyRow(id: 0, keys: chars("קראטוןםפ"), sideInsetUnits: 1.0),
            KeyRow(id: 1, keys: chars("שדגכעיחלךף")),
            KeyRow(
                id: 2,
                keys:
                    chars("זסבהנמצתץ")
                    + [KeySpec(.backspace, width: .remainderShare)]
            )
        ]
    }

    // MARK: Numbers and symbols

    private static func numbers(for language: KeyboardLanguage) -> [KeyRow] {
        // The shekel sign earns its place on an Israeli keyboard; the dollar moves
        // to the symbols plane.
        let currency = language == .hebrew ? "₪" : "$"
        return [
            KeyRow(id: 0, keys: chars("1234567890")),
            KeyRow(id: 1, keys: chars("-/:;()") + chars(currency) + chars("&@\"")),
            KeyRow(
                id: 2,
                keys: [KeySpec(.plane(.symbols, label: "#+="), width: .remainderShare)]
                    + chars(".,?!'")
                    + [KeySpec(.backspace, width: .remainderShare)],
                sideInsetUnits: 0
            )
        ]
    }

    private static func symbols(for language: KeyboardLanguage) -> [KeyRow] {
        [
            KeyRow(id: 0, keys: chars("[]{}#%^*+=")),
            KeyRow(id: 1, keys: chars("_\\|~<>$₪¥•")),
            KeyRow(
                id: 2,
                keys: [KeySpec(.plane(.numbers, label: "123"), width: .remainderShare)]
                    + chars(".,?!'")
                    + [KeySpec(.backspace, width: .remainderShare)],
                sideInsetUnits: 0
            )
        ]
    }

    // MARK: Bottom row

    /// Sparkle and emoji live in the suggestion bar, so this row stays close to
    /// the system layout: plane switch, globe, space, dictation, return.
    public static func bottomRow(
        for language: KeyboardLanguage, plane: KeyboardPlane, showsGlobe: Bool
    ) -> KeyRow {
        let planeKey: KeySpec =
            plane == .letters
            ? KeySpec(.plane(.numbers, label: "123"), width: .unit(1.3))
            : KeySpec(.plane(.letters, label: language == .hebrew ? "אבג" : "ABC"), width: .unit(1.3))

        var keys: [KeySpec] = [planeKey]
        if showsGlobe { keys.append(KeySpec(.globe, width: .unit(1.0))) }
        keys.append(KeySpec(.space, width: .flexible))
        keys.append(KeySpec(.dictation, width: .unit(1.0)))
        keys.append(KeySpec(.ret, width: .unit(2.2)))
        return KeyRow(id: 3, keys: keys)
    }

    // MARK: Width solving

    /// Resolved widths for one row, given the space available.
    ///
    /// The top row of ten equal keys sets the unit; everything else is expressed
    /// in that unit so the columns line up down the whole keyboard.
    public static func widths(
        for row: KeyRow,
        totalWidth: CGFloat,
        unitWidth: CGFloat,
        spacing: CGFloat
    ) -> [CGFloat] {
        let count = CGFloat(row.keys.count)
        guard count > 0 else { return [] }

        let gaps = spacing * (count - 1)
        let inset = row.sideInsetUnits * (unitWidth + spacing) * 2
        let available = max(0, totalWidth - gaps - inset)

        let fixedTotal = row.keys.reduce(CGFloat(0)) { partial, key in
            switch key.width {
            case .unit(let multiple): return partial + unitWidth * multiple
            case .flexible, .remainderShare: return partial
            }
        }

        // Flexible and remainder-share keys both mean "take what the fixed keys
        // left behind", so they split the leftover evenly. The floor keeps shift
        // and delete tappable on a narrow screen.
        let stretchCount = row.keys.filter { $0.width == .flexible || $0.width == .remainderShare }.count
        let leftover = max(0, available - fixedTotal)
        let stretchWidth =
            stretchCount > 0
            ? max(unitWidth * 1.15, leftover / CGFloat(stretchCount))
            : 0

        return row.keys.map { key in
            switch key.width {
            case .unit(let multiple): return unitWidth * multiple
            case .flexible, .remainderShare: return stretchWidth
            }
        }
    }

    /// Width of a standard letter key for a keyboard of this width.
    public static func unitWidth(totalWidth: CGFloat, spacing: CGFloat, sideInset: CGFloat) -> CGFloat {
        let usable = totalWidth - sideInset * 2 - spacing * 9
        return max(20, usable / 10)
    }

    // MARK: Helpers

    private static func chars(_ string: String) -> [KeySpec] {
        string.map { KeySpec(.character(String($0))) }
    }
}
