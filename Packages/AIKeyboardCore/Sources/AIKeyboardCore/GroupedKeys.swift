import Foundation

/// Keys that carry several *neighbouring* letters, so a thumb has a target three
/// to five times the area and a decoder works out which word was meant.
///
/// **A key is a block of the keyboard it replaces, not a run of one row.** The
/// two letter rows that stand clear of shift and delete are merged into one band
/// of double-height keys, and a key is a column slice of that band: `q w` over
/// `a s` is one key, because those four letters are what a thumb aiming at that
/// patch of glass can hit. Grouping only sideways made keys wider and no taller,
/// which is half a target and the wrong half — a thumb misses in both axes.
/// The third row keeps shift and delete, so it stays one row deep and groups
/// sideways as it always did.
///
/// **Nothing moves.** A grouped key covers exactly the cells it swallowed, the
/// band is two rows tall because it replaces two rows, and the keyboard is the
/// same height it was. The letters are where muscle memory left them.
///
/// **The rest of the feature is still an ordinary `LetterLayout`.** A grouped cap
/// is a key whose label happens to read `qw` over `as` and whose long press
/// offers `q`, `w`, `a`, `s`, so `KeyView`, the alternates popup and the
/// left-to-right pinning never learn this feature exists — the same rule
/// `KeyboardCustomization` follows. Only two things had to be taught: a row can
/// be more than one key-height tall, and a cap can carry a line break.
///
/// Measured before it was built: `Bar/grouped/` and `.claude/docs/grouped-keys-design.md`.
public enum GroupedKeys {

    // MARK: The dial

    /// How many letters share a key. Raw value is that number, and `off` is 1 —
    /// which is not a special case anywhere, because a "group" of one letter
    /// produces exactly today's keyboard.
    ///
    /// **The number is a target rather than a promise**, and it is banding that
    /// makes it one: a band key takes whole columns, so it holds an even number
    /// of letters wherever both rows reach. At three per key the band comes out
    /// in twos and fours around a mean of three. The key *count* at every stop is
    /// exactly what `Bar/grouped/` measured, which is what the percentages below
    /// are percentages of.
    public enum Level: Int, CaseIterable, Codable, Sendable {
        case off = 1
        /// 12 keys English, 13 Hebrew, each roughly one letter over another. Measured at
        /// 94.9% English / 91.4% Hebrew top-1, against 98.1% / 97.0% ungrouped.
        /// Leftover columns (`p`, `ךף`) join a neighbour rather than sitting on a
        /// one-letter key.
        case pairs = 2
        /// 7 keys English, 8 Hebrew. 91.3% / 81.9%. English's leftover `p` folds
        /// into the key beside it, so this stop and L2 draw the same English
        /// keyboard; Hebrew still has one more key.
        case l1 = 3
        /// 7 keys in both. 91.3% / 71.2%.
        case l2 = 4
        /// 5 keys English, 6 Hebrew. 82.7% / 67.9% — the Hebrew figure is why
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

        /// Hebrew's usable range ends here. L2 commits the wrong word about three
        /// times in ten; English keeps the stop the user picked.
        public static let hebrewCeiling: Level = .l1

        /// The stop this language actually draws. A shared dial either caps
        /// English early or hands Hebrew a keyboard that guesses wrong too often.
        public func capped(for language: KeyboardLanguage) -> Level {
            guard language == .hebrew, rawValue > Self.hebrewCeiling.rawValue else { return self }
            return .hebrewCeiling
        }

        /// Top-1 decode accuracy measured in `Bar/grouped/results.json`, best
        /// variant per language. Shown in Settings so the trade is stated rather
        /// than discovered.
        ///
        /// **Banding moved these, in both directions, and the Hebrew half is the
        /// cost of the feature rather than a rounding of it.** English gained
        /// where the band pairs a common letter with a rare one under it — +1.8
        /// at L1 and +4.4 at L2 — and Hebrew lost between two and eight points at
        /// every stop, because its two top rows carry far more of its common
        /// letters than English's do and the band puts them on one key. Neither
        /// side of that is visible to the harness's other half: it measures the
        /// decoder assuming the thumb never misses, and a target twice the area
        /// is exactly the thing it cannot see.
        public var measuredAccuracy: (english: Int, hebrew: Int) {
            switch self {
            case .off: return (98, 97)
            case .pairs: return (95, 91)
            case .l1: return (91, 82)
            case .l2: return (91, 71)
            case .l3: return (83, 68)
            }
        }
    }

    // MARK: What a key is

    /// One key: the letters it carries, kept in the rows they came from.
    public struct Group: Equatable, Sendable {
        /// One line per source row this key stands over, top first. A key inside
        /// a band has two; a key on the row that keeps shift and delete has one.
        /// A line may be empty where the row below the band runs out of letters.
        public let lines: [[String]]

        /// How many of the ungrouped keyboard's key positions this one covers.
        /// Used to keep the column budget at ten so the band still fills the row
        /// it replaced; drawn width is `.slot(of: bandCount)`, not this span, so
        /// a leftover column cannot sit on a skinny key beside a fat one.
        public let span: Int

        public init(lines: [[String]], span: Int) {
            self.lines = lines
            self.span = span
        }

        public var letters: [String] { lines.flatMap { $0 } }

        /// What is written on the cap: one line per row, newline-separated.
        ///
        /// Empty lines stay: a leftover column with nothing above it (`ךף`) is
        /// still a band key, and the blank top line is how it draws on the lower
        /// half instead of floating in the middle. `letters(inCap:)` drops the
        /// break, so it is layout rather than a letter.
        public var cap: String {
            let letters = self.letters
            guard letters.count > 1 else { return letters.first ?? "" }
            return lines.map { $0.joined() }.joined(separator: "\n")
        }
    }

    /// One row of the keyboard as drawn, which is not always one row of letters.
    public struct Row: Equatable, Sendable {
        public let groups: [Group]

        /// How many source rows tall this row is drawn — 2 for the band, 1 for
        /// everything else. The keyboard's total height does not change: the band
        /// is two rows tall because it *is* two rows.
        public let heightUnits: Int

        public init(groups: [Group], heightUnits: Int) {
            self.groups = groups
            self.heightUnits = heightUnits
        }

        /// The row's width in units — what the keys inside it add up to.
        public var span: Int { groups.reduce(0) { $0 + $1.span } }
    }

    // MARK: Splitting

    /// How many keys a row of this length becomes.
    ///
    /// **Rounding is half-up.** Ten letters at four per key is 2.5, which
    /// `rounded()` sends to 2 under the banker's rule Foundation uses for `.toNearestOrEven`
    /// and 3 here — the difference between a row of ten becoming two keys or
    /// three. At least one, so a row can never vanish.
    ///
    /// **A band asks it once, for both its rows together**, which is what keeps
    /// the key count at every dial stop exactly the one `Bar/grouped/` measured:
    /// English's 19 banded letters at three per key give six column-groups, then
    /// leftover `p` folds in, so the band draws five keys.
    static func keyCount(rowLength: Int, level: Level) -> Int {
        max(1, Int((Double(rowLength) / Double(level.rawValue) + 0.5).rounded(.down)))
    }

    /// Contiguous groups of roughly equal size, **leading groups taking the
    /// extra**, so ten items in three groups is 4|3|3 and not 3|3|4.
    static func split<T>(_ items: [T], into count: Int) -> [[T]] {
        let count = max(1, count)
        let base = items.count / count
        let extra = items.count % count
        var out: [[T]] = []
        var at = 0
        for index in 0..<count {
            let size = base + (index < extra ? 1 : 0)
            out.append(Array(items[at..<(at + size)]))
            at += size
        }
        return out
    }

    /// The same count of groups, but no group may hold two items that `weight`
    /// scores. `nil` when no such split exists, which is a result rather than a
    /// failure: it means the constraint costs an extra key.
    ///
    /// Exhaustive over contiguous partitions rather than greedy — rows are ten
    /// items, so the search is free, and a greedy rule quietly produces a
    /// lopsided row and calls it the price of the constraint. Ties break toward
    /// the most even split.
    ///
    /// `weight` is a count rather than a flag because a *column* of a band can
    /// carry two of the letters being kept apart, in which case nothing can
    /// separate them and this correctly reports that.
    static func split<T>(_ items: [T], into count: Int, avoiding weight: (T) -> Int) -> [[T]]? {
        let count = max(1, count)
        let ideal = Double(items.count) / Double(count)
        var best: (cost: Double, parts: [[T]])?
        var parts: [[T]] = []

        func walk(_ at: Int, _ left: Int, _ cost: Double) {
            if let found = best, cost >= found.cost { return }
            if left == 0 {
                if at == items.count { best = (cost, parts) }
                return
            }
            let maximum = items.count - at - (left - 1)
            guard maximum >= 1 else { return }
            for size in 1...maximum {
                let piece = Array(items[at..<(at + size)])
                if piece.reduce(0, { $0 + weight($1) }) > 1 { continue }
                parts.append(piece)
                let deviation = Double(size) - ideal
                walk(at + size, left - 1, cost + deviation * deviation)
                parts.removeLast()
            }
        }

        walk(0, count, 0)
        return best?.parts
    }

    /// One row's letters in contiguous groups of roughly `level` each.
    static func split(_ row: [String], level: Level) -> [[String]] {
        split(row, into: keyCount(rowLength: row.count, level: level))
    }

    /// The same key count, with no group holding two letters of `avoid`.
    static func split(_ row: [String], level: Level, avoiding avoid: Set<String>) -> [[String]]? {
        split(row, into: keyCount(rowLength: row.count, level: level)) {
            avoid.contains($0) ? 1 : 0
        }
    }

    // MARK: Hebrew

    /// The seven single letters Hebrew glues to the front of a word: ה the, ב in,
    /// ל to, מ from, ו and, ש that, כ as.
    ///
    /// **Keeping them off one another's keys is the single biggest Hebrew win
    /// available and it costs no keys at all** — only different boundaries, so
    /// the letters stay in order and muscle memory survives. Worth +7.0 points at
    /// thirteen keys and +6.6 at eight. Plain adjacency puts ה with מ, which makes "the
    /// X" and "from X" the same keystroke, in a language where every sentence has
    /// one.
    ///
    /// **Banding made this easier rather than harder, which was not a given.** A
    /// column of the band is atomic — both its letters are on one key, and no
    /// partition can pull them apart — so a column holding two clitics would have
    /// been an unfixable collision. Hebrew's band is `קראטוןםפ` over `שדגכעיחלךף`
    /// and no column of it holds two: ו sits over ע, and ש, כ and ל are in
    /// columns of their own. The row that is left, `זסבהנמצתץ`, holds three
    /// clitics and splits the way it always did.
    public static let hebrewClitics: Set<String> = ["ה", "ב", "ל", "מ", "ו", "ש", "כ"]

    // MARK: Planning a layout

    /// One language's letter rows as the keyboard will draw them.
    static func plan(for rows: [[String]], language: KeyboardLanguage, level: Level) -> [Row] {
        plan(for: rows, keepingApart: language == .hebrew ? hebrewClitics : [], level: level)
    }

    /// The same, told which letters to keep apart rather than which language it
    /// is, so the grouping can be exercised with no keyboard around it. See
    /// `Bar/grouped/harness/swift-check.sh`.
    static func plan(for rows: [[String]], keepingApart avoid: Set<String>, level: Level) -> [Row] {
        guard level != .off else {
            return rows.map { row in
                Row(groups: row.map { Group(lines: [[$0]], span: 1) }, heightUnits: 1)
            }
        }
        // **The top two rows band and the last one does not**, because the last
        // one is where shift and delete stand. A pinned key inside a
        // double-height row would have to be double-height too, and the row it
        // shares would then be the only place on the keyboard where the letters
        // are not the tallest thing in it.
        guard rows.count >= 3 else {
            return rows.map { single($0, keepingApart: avoid, level: level) }
        }
        return [band(rows[0], rows[1], keepingApart: avoid, level: level)]
            + rows[2...].map { single($0, keepingApart: avoid, level: level) }
    }

    /// A row that groups sideways only: the one that carries shift and delete.
    private static func single(
        _ row: [String], keepingApart avoid: Set<String>, level: Level
    )
        -> Row
    {
        let count = keyCount(rowLength: row.count, level: level)
        let parts =
            (avoid.isEmpty
                ? nil
                : split(row, into: count, avoiding: { avoid.contains($0) ? 1 : 0 }))
            ?? split(row, into: count)
        let groups = absorbingSingletons(
            parts.map { Group(lines: [$0], span: $0.count) }, keepingApart: avoid)
        return Row(groups: groups, heightUnits: 1)
    }

    /// Two rows merged into one row of double-height keys.
    ///
    /// **The shorter row is left-aligned under the longer one**, which is the
    /// choice that keeps today's pairs: `qw` sits over `as` and `op` over `l`,
    /// exactly the boundaries the row-at-a-time grouping already used. The other
    /// alignment moves every letter of the lower row one column right for no
    /// gain — the rows are staggered by half a key on screen either way, and a
    /// key's two lines are each centred inside it, so the letters land within
    /// half a key of where they have always been.
    private static func band(
        _ top: [String], _ bottom: [String], keepingApart avoid: Set<String>, level: Level
    ) -> Row {
        let width = max(top.count, bottom.count)
        let columns = (0..<width).map { index in
            Column(
                top: index < top.count ? top[index] : nil,
                bottom: index < bottom.count ? bottom[index] : nil)
        }
        // Never more keys than columns: at two letters per key a band of 19
        // letters wants ten keys and has exactly ten columns to put them in.
        let count = min(width, keyCount(rowLength: top.count + bottom.count, level: level))
        let parts =
            (avoid.isEmpty
                ? nil
                : split(columns, into: count, avoiding: { $0.clitics(in: avoid) }))
            ?? split(columns, into: count)
        let groups = absorbingSingletons(
            parts.map { part in
                Group(
                    lines: [part.compactMap(\.top), part.compactMap(\.bottom)],
                    span: part.count)
            },
            keepingApart: avoid)
        return Row(groups: groups, heightUnits: 2)
    }

    /// Fold any one-letter group into a neighbour. English `p` and Hebrew `ף`
    /// sit on leftover columns with nothing above or below them, and the split
    /// otherwise leaves them on a key of their own — a single character on a
    /// skinny button, which is the opposite of this feature. Two leftovers next
    /// to each other join first (`ך` with `ף`); otherwise the letter joins the
    /// neighbour that does not put two Hebrew prefixes on one key.
    private static func absorbingSingletons(
        _ groups: [Group], keepingApart avoid: Set<String>
    ) -> [Group] {
        var groups = groups
        while groups.count > 1, let index = groups.firstIndex(where: { $0.letters.count == 1 }) {
            let target = mergeTarget(for: index, in: groups, keepingApart: avoid)
            let lo = min(index, target)
            let hi = max(index, target)
            groups[lo] = merged(groups[lo], groups[hi])
            groups.remove(at: hi)
        }
        return groups
    }

    /// Which neighbour a singleton should join. Prefers another singleton (so
    /// two leftover columns become one key) and otherwise the side that keeps
    /// Hebrew prefixes apart; left wins a tie, which is the leftover sitting
    /// on the right of a left-aligned shorter row.
    private static func mergeTarget(
        for index: Int, in groups: [Group], keepingApart avoid: Set<String>
    ) -> Int {
        let neighbors = [index - 1, index + 1].filter { groups.indices.contains($0) }
        func collides(_ other: Int) -> Bool {
            clitics(in: groups[index], avoid: avoid) + clitics(in: groups[other], avoid: avoid) > 1
        }
        let safeSingletons = neighbors.filter {
            groups[$0].letters.count == 1 && !collides($0)
        }
        if let pick = safeSingletons.first { return pick }
        let safe = neighbors.filter { !collides($0) }
        return (safe.first ?? neighbors.first) ?? index
    }

    private static func clitics(in group: Group, avoid: Set<String>) -> Int {
        group.letters.filter(avoid.contains).count
    }

    private static func merged(_ left: Group, _ right: Group) -> Group {
        let lineCount = max(left.lines.count, right.lines.count)
        let lines = (0..<lineCount).map { index in
            (index < left.lines.count ? left.lines[index] : [])
                + (index < right.lines.count ? right.lines[index] : [])
        }
        return Group(lines: lines, span: left.span + right.span)
    }

    /// One key position of the ungrouped keyboard, and the one under it.
    private struct Column {
        let top: String?
        let bottom: String?

        func clitics(in avoid: Set<String>) -> Int {
            [top, bottom].compactMap { $0 }.filter(avoid.contains).count
        }
    }

    /// The letters on each key, drawn row by drawn row. What the decoder numbers.
    static func groups(
        for rows: [[String]], language: KeyboardLanguage, level: Level
    )
        -> [[[String]]]
    {
        plan(for: rows, language: language, level: level).map { $0.groups.map(\.letters) }
    }

    /// The same from an explicit set of letters to keep apart.
    static func groups(
        for rows: [[String]], keepingApart avoid: Set<String>, level: Level
    )
        -> [[[String]]]
    {
        plan(for: rows, keepingApart: avoid, level: level).map { $0.groups.map(\.letters) }
    }

    // MARK: Building the layout

    /// The long presses a planned layout offers, keyed by cap.
    ///
    /// **The long press is the escape hatch, and it is why the rule that a person
    /// can always type exactly what they meant survives this feature.** Grouped
    /// keys destroy the premise that slot zero holds the literal keystrokes —
    /// there is no literal — so the guarantee becomes "there is always a route to
    /// the exact letter", and this is that route. It costs nothing to build
    /// because `KeyView` has drawn alternates since the accents landed.
    ///
    /// A group's own alternates are dropped: holding a four-letter key has to
    /// offer the four letters, and cannot also offer eight accents. Accents remain
    /// reachable with grouping off, and `GroupedKeysTests` pins that.
    static func alternates(for rows: [Row], base: KeyboardLayout.LetterLayout) -> [String: [String]] {
        var out: [String: [String]] = [:]
        for group in rows.flatMap(\.groups) {
            let letters = group.letters
            // A one-letter group is an ordinary key and keeps its accents.
            out[group.cap] = letters.count == 1 ? (base.alternates[group.cap] ?? []) : letters
        }
        return out
    }

    /// A grouped `LetterLayout`: one entry per drawn row, each cap carrying the
    /// letters it merged. The shape the rest of the layout engine reads.
    static func layout(
        _ base: KeyboardLayout.LetterLayout, language: KeyboardLanguage, level: Level
    )
        -> KeyboardLayout.LetterLayout
    {
        guard level != .off, supports(language) else { return base }
        let rows = plan(for: base.rows, language: language, level: level)
        return KeyboardLayout.LetterLayout(
            keys: rows.map { $0.groups.map(\.cap) },
            hasCase: base.hasCase,
            alternates: alternates(for: rows, base: base))
    }

    /// Which letters a cap carries. One entry for an ordinary key.
    ///
    /// Splitting the cap rather than storing a parallel table, because the cap is
    /// already the joined form and two spellings of one fact drift. The line
    /// breaks a banded cap carries are layout, not letters, so they are dropped
    /// here — which is also why a cap may never be typed straight into the
    /// document: `KeyboardController.isGroupedCap` routes anything wider than one
    /// letter through the decoder.
    ///
    /// Sound only because `supports(_:)` refuses any language whose letters are
    /// not single `Character`s — see there.
    public static func letters(inCap cap: String) -> [String] {
        cap.filter { !$0.isNewline }.map(String.init)
    }

    /// The lines a cap is drawn on, empty rows kept. Same split `KeySpec.groupedLines`
    /// uses; here so a tap can be named without a `KeySpec`.
    public static func lines(inCap cap: String) -> [[String]] {
        cap.split(separator: "\n", omittingEmptySubsequences: false).map { $0.map(String.init) }
    }

    /// Which letter a tap on this key meant, or `nil` when the tap is too close
    /// to the middle to call.
    ///
    /// `x` and `y` are 0...1 in the key, origin top-left. The key is sliced the
    /// way it is drawn: one band per line, equal columns per letter on that line.
    /// An empty line (the blank top of `ךף`) occupies its slice and yields
    /// nothing. A dead band around every *internal* boundary leaves a thumb that
    /// aimed at the key, not at a letter, for the decoder — the same idea as a
    /// long press, which is the hard version of this pin.
    public static func letter(
        atX x: Double, y: Double, in lines: [[String]], deadBand: Double = 0.18
    ) -> String? {
        guard !lines.isEmpty else { return nil }
        let x = min(1, max(0, x))
        let y = min(1, max(0, y))
        let rowCount = lines.count
        let rowFrac = y * Double(rowCount)
        var row = Int(rowFrac)
        if row >= rowCount { row = rowCount - 1 }
        let line = lines[row]
        guard !line.isEmpty else { return nil }
        let colCount = line.count
        let colFrac = x * Double(colCount)
        var col = Int(colFrac)
        if col >= colCount { col = colCount - 1 }
        let fy = rowFrac - Double(row)
        let fx = colFrac - Double(col)
        if rowCount > 1 {
            if row > 0, fy < deadBand { return nil }
            if row < rowCount - 1, fy > 1 - deadBand { return nil }
        }
        if colCount > 1 {
            if col > 0, fx < deadBand { return nil }
            if col < colCount - 1, fx > 1 - deadBand { return nil }
        }
        return line[col]
    }

    /// Whether this language may be grouped at all.
    ///
    /// **Refuses any layout whose letters fuse when they are joined, and that is
    /// not fussiness.** `KeyboardController.press` receives the cap string and
    /// nothing else, so the only way back to "which letters is this key" is to
    /// split the cap — and a Devanagari key is a combining mark that is *one*
    /// `Character` on its own and joins with its neighbour into one grapheme
    /// cluster, so `ौैा` splits into a single "letter" no key ever carried. The
    /// long press then offers a fused mark instead of the three letters, which is
    /// the escape hatch failing in the one way that traps the user. Same trap
    /// `LetterLayout.init(keys:)` exists for: written as a string, InScript's top
    /// row measures 7 instead of 11.
    ///
    /// **The question is about a pair, not about a key, and asking it about a key
    /// is what let Devanagari through.** Every InScript key *is* one `Character`,
    /// so the earlier `$0.count == 1` answered yes to a layout this feature
    /// destroys. Doubling a letter is the cheapest form of the real question: a
    /// base character gives two `Character`s and a combining mark gives one. It
    /// covers banding as well as row runs, where a per-row check would not — a
    /// band joins a letter from the top row to the one *underneath* it, which are
    /// adjacent in no row.
    ///
    /// English and Hebrew are the two this was measured on and both pass; anything
    /// that does not simply never sees the feature, which is better than a
    /// keyboard that types letters nobody pressed.
    public static func supports(_ language: KeyboardLanguage) -> Bool {
        guard let layout = KeyboardLayout.letterLayouts[language] else { return false }
        return layout.rows.allSatisfy { row in
            row.allSatisfy { $0.count == 1 && ($0 + $0).count == 2 }
        }
    }

    /// Whether a generated word list is in the bundle. Settings reads this so it
    /// can say the feature is running on a few hundred seed words rather than
    /// letting somebody discover that by typing.
    public static func hasBundledLexicon(for language: KeyboardLanguage) -> Bool {
        GroupedLexiconResource.isBundled(language)
    }
}
