import Foundation

/// Keys that carry several adjacent letters, so a thumb has a target three to
/// five times wider and a decoder works out which word was meant.
///
/// **The whole feature is a `LetterLayout` transform, and that is deliberate.**
/// `LetterLayout.rows` is already `[[String]]` with one entry per key, and
/// `alternates` is already keyed by the string on the cap — so a grouped key is
/// an ordinary key whose label happens to be `"qwer"` and whose long press
/// offers `q`, `w`, `e`, `r`. The width solver, `KeyView`, the alternates popup
/// and the left-to-right pinning never learn this feature exists, which is the
/// same rule `KeyboardCustomization` follows.
///
/// Measured before it was built: `Bar/grouped/` and `.claude/docs/grouped-keys-design.md`.
public enum GroupedKeys {

    // MARK: The dial

    /// How many letters share a key. Raw value is that number, and `off` is 1 —
    /// which is not a special case anywhere, because a "group" of one letter
    /// produces exactly today's keyboard.
    public enum Level: Int, CaseIterable, Codable, Sendable {
        case off = 1
        /// 14 keys in both languages. Measured at 96.5% English / 93.5% Hebrew
        /// top-1, against 98.1% / 97.0% ungrouped — so it costs about a point and
        /// a half and doubles the target.
        case pairs = 2
        /// 8 keys English, 9 Hebrew. 90.5% / 86.7%.
        case l1 = 3
        /// 7 keys in both. 86.9% / 79.1%.
        case l2 = 4
        /// 5 keys English, 6 Hebrew. 81.1% / 71.3% — the Hebrew figure is why
        /// this one carries a warning in Settings rather than being offered flat.
        case l3 = 5

        public var title: String {
            switch self {
            case .off: return "Off"
            case .pairs: return "Two letters"
            case .l1: return "Three letters"
            case .l2: return "Four letters"
            case .l3: return "Five letters"
            }
        }

        /// Top-1 decode accuracy measured in `Bar/grouped/results.json`, best
        /// variant per language. Shown in Settings so the trade is stated rather
        /// than discovered.
        public var measuredAccuracy: (english: Int, hebrew: Int) {
            switch self {
            case .off: return (98, 97)
            case .pairs: return (97, 94)
            case .l1: return (91, 87)
            case .l2: return (87, 79)
            case .l3: return (81, 71)
            }
        }
    }

    // MARK: Splitting a row

    /// How many keys a row of this length becomes.
    ///
    /// **Rounding is half-up.** Ten letters at four per key is 2.5, which
    /// `rounded()` sends to 2 under the banker's rule Foundation uses for `.toNearestOrEven`
    /// and 3 here — the difference between a row of ten becoming two keys or
    /// three. At least one, so a row can never vanish.
    static func keyCount(rowLength: Int, level: Level) -> Int {
        max(1, Int((Double(rowLength) / Double(level.rawValue) + 0.5).rounded(.down)))
    }

    /// Contiguous groups of roughly `level` letters, **leading groups taking the
    /// extra**, so `qwertyuiop` at three is `qwer|tyu|iop` and not `qwe|rty|uiop`.
    static func split(_ row: [String], level: Level) -> [[String]] {
        let count = keyCount(rowLength: row.count, level: level)
        let base = row.count / count
        let extra = row.count % count
        var out: [[String]] = []
        var at = 0
        for index in 0..<count {
            let size = base + (index < extra ? 1 : 0)
            out.append(Array(row[at..<(at + size)]))
            at += size
        }
        return out
    }

    /// The same key count, but no group may hold two letters of `avoid`.
    /// `nil` when no such split exists, which is a result rather than a failure:
    /// it means the constraint costs an extra key.
    ///
    /// Exhaustive over contiguous partitions rather than greedy — rows are ten
    /// letters, so the search is free, and a greedy rule quietly produces a
    /// lopsided row and calls it the price of the constraint. Ties break toward
    /// the most even split.
    static func split(_ row: [String], level: Level, avoiding avoid: Set<String>) -> [[String]]? {
        let count = keyCount(rowLength: row.count, level: level)
        let ideal = Double(row.count) / Double(count)
        var best: (cost: Double, parts: [[String]])?
        var parts: [[String]] = []

        func walk(_ at: Int, _ left: Int, _ cost: Double) {
            if let found = best, cost >= found.cost { return }
            if left == 0 {
                if at == row.count { best = (cost, parts) }
                return
            }
            let maximum = row.count - at - (left - 1)
            guard maximum >= 1 else { return }
            for size in 1...maximum {
                let piece = Array(row[at..<(at + size)])
                if piece.filter(avoid.contains).count > 1 { continue }
                parts.append(piece)
                let deviation = Double(size) - ideal
                walk(at + size, left - 1, cost + deviation * deviation)
                parts.removeLast()
            }
        }

        walk(0, count, 0)
        return best?.parts
    }

    // MARK: Hebrew

    /// The seven single letters Hebrew glues to the front of a word: ה the, ב in,
    /// ל to, מ from, ו and, ש that, כ as.
    ///
    /// **Keeping them off one another's keys is the single biggest Hebrew win
    /// available and it costs no keys at all** — only different boundaries, so
    /// the letters stay in order and muscle memory survives. Worth +4.9 points at
    /// 14 keys and +2.3 at nine. Plain adjacency puts ה with מ at L1, which makes
    /// "the X" and "from X" the same keystroke, in a language where every
    /// sentence has one.
    ///
    /// It runs out rather than snapping: the row `זסבהנמצתץ` holds three of them
    /// and gets two keys from L2 down, so one key must take two. `groups(for:)`
    /// keeps whatever separation is still reachable.
    public static let hebrewClitics: Set<String> = ["ה", "ב", "ל", "מ", "ו", "ש", "כ"]

    // MARK: Building the layout

    /// One language's rows regrouped, each key holding the letters it merged.
    static func groups(for rows: [[String]], language: KeyboardLanguage, level: Level) -> [[[String]]] {
        groups(for: rows, keepingApart: language == .hebrew ? hebrewClitics : [], level: level)
    }

    /// The same, told which letters to keep apart rather than which language it
    /// is, so the grouping can be exercised with no keyboard around it. See
    /// `Bar/grouped/harness/swift-check.sh`.
    static func groups(
        for rows: [[String]], keepingApart avoid: Set<String>, level: Level
    )
        -> [[[String]]]
    {
        guard level != .off else { return rows.map { $0.map { [$0] } } }
        return rows.map { row in
            if !avoid.isEmpty, let separated = split(row, level: level, avoiding: avoid) {
                return separated
            }
            return split(row, level: level)
        }
    }

    /// A grouped `LetterLayout`: the cap shows the letters it carries, and its
    /// long press offers them one at a time.
    ///
    /// **The long press is the escape hatch, and it is why the rule that a person
    /// can always type exactly what they meant survives this feature.** Grouped
    /// keys destroy the premise that slot zero holds the literal keystrokes —
    /// there is no literal — so the guarantee becomes "there is always a route to
    /// the exact letter", and this is that route. It costs nothing to build
    /// because `KeyView` has drawn alternates since the accents landed.
    ///
    /// A group's own alternates are dropped: holding `[qwer]` has to offer the
    /// four letters, and cannot also offer eight accents. Accents remain reachable
    /// with grouping off, and `GroupedKeysTests` pins that.
    static func layout(
        _ base: KeyboardLayout.LetterLayout, language: KeyboardLanguage, level: Level
    )
        -> KeyboardLayout.LetterLayout
    {
        guard level != .off, supports(language) else { return base }
        let grouped = groups(for: base.rows, language: language, level: level)
        var rows: [[String]] = []
        var alternates: [String: [String]] = [:]
        for row in grouped {
            var caps: [String] = []
            for group in row {
                let cap = group.joined()
                caps.append(cap)
                // A one-letter group is an ordinary key and keeps its accents.
                alternates[cap] = group.count == 1 ? (base.alternates[cap] ?? []) : group
            }
            rows.append(caps)
        }
        return KeyboardLayout.LetterLayout(
            keys: rows, hasCase: base.hasCase, alternates: alternates)
    }

    /// Which letters a cap carries. One entry for an ordinary key.
    ///
    /// Splitting the cap rather than storing a parallel table, because the cap is
    /// already the joined form and two spellings of one fact drift. Sound only
    /// because `supports(_:)` refuses any language whose letters are not single
    /// `Character`s — see there.
    public static func letters(inCap cap: String) -> [String] {
        cap.map(String.init)
    }

    /// Whether this language may be grouped at all.
    ///
    /// **Refuses any layout with a multi-`Character` key, and that is not
    /// fussiness.** `KeyboardController.press` receives the cap string and
    /// nothing else, so the only way back to "which letters is this key" is to
    /// split the cap — and a Devanagari key is a run of combining marks that is
    /// *one* `Character` written as several scalars, so `ौैा` splits into
    /// letters no key ever carried. That is the same trap `LetterLayout.init(keys:)`
    /// exists for: written as a string, InScript's top row measures 7 instead of
    /// 11. English and Hebrew are the two this was measured on and both pass;
    /// anything that does not simply never sees the feature, which is better than
    /// a keyboard that types letters nobody pressed.
    public static func supports(_ language: KeyboardLanguage) -> Bool {
        guard let layout = KeyboardLayout.letterLayouts[language] else { return false }
        return layout.rows.allSatisfy { row in
            row.allSatisfy { $0.count == 1 && $0.unicodeScalars.count <= 2 }
        }
    }
}
