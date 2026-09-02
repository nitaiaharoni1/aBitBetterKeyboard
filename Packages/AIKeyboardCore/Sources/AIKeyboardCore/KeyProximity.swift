import Foundation

/// Where one finger landed inside a key, including the conservative part of
/// the contact radius the hardware says is definitely present.
///
/// The four values are normalised to the key's own box: `x == 0` is its left
/// edge, `x == 1` its right edge, and a horizontal radius of `0.5` is half a
/// key wide. Keeping this independent of UIKit lets the suggestion harness use
/// the exact production scorer without pretending it has real fingers.
struct KeyTouchEvidence: Equatable, Sendable {
    let x: Double
    let y: Double
    let horizontalRadius: Double
    let verticalRadius: Double
    let sequenceID: UUID?

    init(
        x: Double, y: Double, horizontalRadius: Double = 0, verticalRadius: Double = 0,
        sequenceID: UUID? = nil
    ) {
        self.x = x
        self.y = y
        self.horizontalRadius = max(0, horizontalRadius)
        self.verticalRadius = max(0, verticalRadius)
        self.sequenceID = sequenceID
    }

    /// How strongly this touch points toward a neighbouring key at this offset.
    /// Zero is a centred touch; one is a centre at or beyond the shared edge.
    func support(toward offset: KeyProximity.Offset) -> Double {
        let horizontal =
            offset.dx < 0
            ? edgeSupport(distance: x, radius: horizontalRadius)
            : offset.dx > 0
                ? edgeSupport(distance: 1 - x, radius: horizontalRadius) : 0
        let vertical =
            offset.dy < 0
            ? edgeSupport(distance: y, radius: verticalRadius)
            : offset.dy > 0
                ? edgeSupport(distance: 1 - y, radius: verticalRadius) : 0
        let horizontalWeight = abs(offset.dx)
        let verticalWeight = abs(offset.dy)
        let totalWeight = horizontalWeight + verticalWeight
        guard totalWeight > 0 else { return 0 }
        return min(
            1,
            (horizontal * horizontalWeight + vertical * verticalWeight) / totalWeight)
    }

    private func edgeSupport(distance rawDistance: Double, radius: Double) -> Double {
        let distance = max(0, rawDistance)
        // The centre alone is already useful: it rises smoothly from zero at
        // the middle of the key to one at the edge. The radius adds evidence
        // only for the part of the finger that certainly crossed that edge.
        let centreSupport = min(1, max(0, 1 - distance * 2))
        guard radius > 0 else { return centreSupport }
        let contactSupport = min(1, max(0, (radius - distance) / radius))
        return max(centreSupport, contactSupport)
    }
}

/// The touch evidence that belongs to the word currently under the caret.
///
/// It is deliberately ephemeral. The controller drops it when the surrounding
/// text changes, so geometry from one field or one occurrence of a word can
/// never influence another.
struct TypingTouchTrace: Equatable, Sendable {
    struct Sample: Equatable, Sendable {
        let evidence: KeyTouchEvidence
        let language: KeyboardLanguage
    }

    var spelling = ""
    var context = ""
    var touches: [Sample?] = []

    init() {}

    mutating func record(
        inserted: String, evidence: KeyTouchEvidence?, language: KeyboardLanguage,
        word: String, context newContext: String
    ) {
        let insertedCount = inserted.count
        if context == newContext, word == spelling + inserted {
            spelling = word
            touches.append(
                contentsOf: evidenceForInsertion(
                    count: insertedCount, evidence: evidence, language: language))
            return
        }

        spelling = word
        context = newContext
        touches = Array(repeating: nil, count: word.count)
        guard insertedCount == 1, word.hasSuffix(inserted), !touches.isEmpty else { return }
        if let evidence {
            touches[touches.count - 1] = Sample(evidence: evidence, language: language)
        }
    }

    mutating func evidence(matching word: String, context newContext: String) -> TypingTouchTrace? {
        guard context == newContext else {
            clear()
            return nil
        }
        if spelling != word {
            guard spelling.hasPrefix(word), word.count < spelling.count else {
                clear()
                return nil
            }
            spelling = word
            touches.removeLast(touches.count - word.count)
        }
        guard spelling == word, touches.count == word.count, touches.contains(where: { $0 != nil })
        else { return nil }
        return self
    }

    /// Aligns the physical slots with the word dictionaries score after leading
    /// and trailing punctuation has been removed. The stored trace stays raw so
    /// another typed character can still extend it normally.
    func aligned(to core: String) -> TypingTouchTrace? {
        guard !core.isEmpty, let range = spelling.range(of: core) else { return nil }
        let start = spelling.distance(from: spelling.startIndex, to: range.lowerBound)
        let count = core.count
        guard start + count <= touches.count else { return nil }
        var aligned = self
        aligned.spelling = core
        aligned.touches = Array(touches[start..<(start + count)])
        return aligned
    }

    mutating func clear() {
        spelling = ""
        context = ""
        touches.removeAll(keepingCapacity: true)
    }

    /// Directional support for same-length neighbouring-key substitutions.
    /// Insertions, deletions and phonetic corrections carry no touch claim.
    func support(for candidate: String) -> Double {
        let typed = Array(spelling.lowercased())
        let proposed = Array(candidate.lowercased())
        guard typed.count == proposed.count, typed.count == touches.count else { return 0 }

        var support = 0.0
        var changes = 0
        for index in typed.indices where typed[index] != proposed[index] {
            guard let sample = touches[index],
                KeyProximity.hasExactTouchGeometry(for: sample.language),
                let offset = KeyProximity.offset(
                    from: typed[index], to: proposed[index], in: sample.language)
            else { return 0 }
            support += sample.evidence.support(toward: offset)
            changes += 1
        }
        guard changes > 0 else { return 0 }
        return support / Double(changes)
    }

    private func evidenceForInsertion(
        count: Int, evidence: KeyTouchEvidence?, language: KeyboardLanguage
    ) -> [Sample?] {
        guard count == 1 else { return Array(repeating: nil, count: count) }
        return [evidence.map { Sample(evidence: $0, language: language) }]
    }
}

/// Whether two letters sit next to each other on the letter plane.
///
/// **Offers only.** A fat-finger substitution may climb inside the neighbour
/// tier; `commitReason` still commits a same-length neighbour only when
/// `SeedLanguageModel.isTransposition` says so. The rows are written out
/// rather than read from `KeyboardLayout`, because the typing harness copies
/// this file and does not compile that one.
///
/// **A row's raw key index is not its position on screen, and treating it as
/// one was the bug.** `KeyboardLayout.widths(for:)` gives every letter row the
/// same key width and centres each row's own key count inside the same
/// reference width (`KeyboardLayout+WidthSolver.swift`), so an 8-key row and
/// a 10-key row drawn across the same 396pt do not share a column grid —
/// index 7 of the 8-key row sits at 78% of the row, index 7 of the 10-key row
/// sits at 75%, and the gap widens moving right. Comparing raw indices with
/// `colGap <= 1` was comparing two different rulers. `normalizedCenter`
/// rebuilds the one measurement that matters — where a key actually is,
/// as a fraction of one key width — from the same facts
/// `KeyboardLayout.letters(for:)` and `KeyboardLayout+WidthSolver.swift` use:
/// how many letters are in the row, and whether shift or delete pins one or
/// both of its ends. It does not import either file; see below for what is
/// duplicated and why that is safe.
///
/// **What changed and what did not, measured against `rowShapes` below.**
/// Same-row adjacency is untouched — two letters typed in the same row are
/// exactly one key apart or they are not, and that is still a raw index
/// test. Two rows apart is still never adjacent. Only a *neighbouring* row
/// pair moved, and only by getting stricter: the geometry never makes a pair
/// adjacent that the old index test called apart, it only drops pairs the
/// index test called adjacent by chance of sharing an index. For Hebrew's
/// shipped 8/10/9 rows this drops exactly fifteen pairs and adds none —
/// **top row against middle row**, the top letter losing its index-aligned
/// neighbour one column early because the top row sits to the *right* of
/// where its own index would put it (delete pins its far end, so nothing
/// centres it): ר/ש, א/ד, ט/ג, ו/כ, ן/ע, ם/י, פ/ח all stop being adjacent —
/// **middle row against bottom row**, the same drop mirrored to the other
/// side, because the bottom row sits to the *right* of the middle row by
/// almost exactly half a key: ש/ס, ד/ב, ג/ה, כ/נ, ע/מ, י/צ, ח/ת, ל/ץ all stop
/// being adjacent. Every pair the geometry still calls adjacent — א/ט in the
/// same row, פ/ך across rows, every English pair pinned in the test file —
/// was already adjacent under the old test and stays that way; none of them
/// is close enough under the new one to have been in danger.
enum KeyProximity {

    struct Offset {
        let dx: Double
        let dy: Double
    }

    /// Touch direction is used only where this file mirrors the shipped layout
    /// exactly. Other languages keep text-only ranking rather than borrowing
    /// QWERTY geometry that may point at a different physical key.
    static func hasExactTouchGeometry(for language: KeyboardLanguage) -> Bool {
        language == .english || language == .hebrew
    }

    static func rows(for language: KeyboardLanguage) -> [String] {
        if language == .hebrew {
            return ["קראטוןםפ", "שדגכעיחלךף", "זסבהנמצתץ"]
        }
        return ["qwertyuiop", "asdfghjkl", "zxcvbnm"]
    }

    /// Same row at col±1. A neighbouring row when the two keys' normalised
    /// centres sit within one key width of each other (below). Never a
    /// transposition, never two rows apart.
    static func areAdjacent(_ a: Character, _ b: Character, in language: KeyboardLanguage) -> Bool {
        offset(from: a, to: b, in: language) != nil
    }

    /// The neighbouring key's screen-space offset from the key that was typed.
    /// Kept beside `areAdjacent` so ranking and directional touch evidence use
    /// one geometry and cannot disagree about which pairs are reachable.
    static func offset(
        from a: Character, to b: Character, in language: KeyboardLanguage
    ) -> Offset? {
        let letters = rows(for: language)
        guard let first = position(of: a, in: letters), let second = position(of: b, in: letters)
        else { return nil }
        let rowGap = abs(first.row - second.row)
        if rowGap == 0 {
            guard abs(first.col - second.col) == 1 else { return nil }
            return Offset(dx: Double(second.col - first.col), dy: 0)
        }
        guard rowGap == 1 else { return nil }
        let shapes = rowShapes(for: language, letters: letters)
        let centerA = normalizedCenter(row: first.row, col: first.col, letters: letters, shapes: shapes)
        let centerB = normalizedCenter(row: second.row, col: second.col, letters: letters, shapes: shapes)
        guard abs(centerA - centerB) < adjacentThresholdKeyWidths else { return nil }
        return Offset(dx: centerB - centerA, dy: Double(second.row - first.row))
    }

    /// Same length, exactly one index differs, those two characters are
    /// adjacent. A transposition differs at two indexes and is not this.
    static func isAdjacentSubstitution(
        _ typed: String, _ other: String, in language: KeyboardLanguage
    ) -> Bool {
        guard typed.count == other.count, !typed.isEmpty else { return false }
        var mismatch: (Character, Character)?
        for (left, right) in zip(typed, other) {
            guard fold(left) != fold(right) else { continue }
            if mismatch != nil { return false }
            mismatch = (left, right)
        }
        guard let pair = mismatch else { return false }
        return areAdjacent(pair.0, pair.1, in: language)
    }

    private static func fold(_ letter: Character) -> Character {
        String(letter).lowercased().first ?? letter
    }

    private static func position(
        of raw: Character, in letters: [String]
    ) -> (row: Int, col: Int)? {
        let needle = fold(raw)
        for (row, rowLetters) in letters.enumerated() {
            if let index = rowLetters.firstIndex(of: needle) {
                return (row, rowLetters.distance(from: rowLetters.startIndex, to: index))
            }
        }
        return nil
    }

    // MARK: Row geometry

    /// Whether a row's leading or trailing end is pinned by shift or delete.
    /// A pinned end holds its width regardless of how many letters share the
    /// row with it, which is what pulls the letters between the pins off the
    /// row's own raw-index centre.
    private struct RowShape {
        let leadingPinned: Bool
        let trailingPinned: Bool
        let horizontalOffset: Double
    }

    /// **Mirrors `KeyboardLayout.deleteRow(of:)` and the shift line in
    /// `KeyboardLayout.letters(for:)`, rather than hardcoding which language
    /// gets which.** Deriving it from the row spans this file already carries
    /// means a row that gains or loses a letter cannot silently disagree with
    /// its own pin placement; only `hasCase` — Hebrew has no shift key, and no
    /// third language is modelled here — is a fact this file has to be told
    /// rather than one it can read off its own rows.
    private static func rowShapes(for language: KeyboardLanguage, letters: [String]) -> [RowShape] {
        let spans = letters.map(\.count)
        let hasCase = language != .hebrew
        let deleteRow =
            spans.count == 3 && spans[0] < spans[1] && spans[0] < spans[2] ? 0 : spans.count - 1
        return spans.indices.map { index in
            RowShape(
                leadingPinned: hasCase && index == spans.count - 1,
                trailingPinned: index == deleteRow,
                horizontalOffset: language == .hebrew && index == 0
                    ? hebrewTopRowOffset : 0)
        }
    }

    /// Gap between two keys in the same row, in key widths.
    ///
    /// **A measured ratio, not a geometric constant, and it is the one number
    /// in this file that is only exact on the device it was measured on.**
    /// `Theme.Metrics.keySpacing` is a fixed 4pt; the key width it is divided
    /// by grows with the screen, so this ratio shrinks a few percent on a
    /// wider phone and grows a few percent on a narrower one. iPhone 17 Pro:
    /// a 402pt-wide screen gives a 36pt reference key width, which is the
    /// same arithmetic `KeyboardLayout.pinnedWidth`'s own doc comment works
    /// from.
    ///
    /// **That it does not matter was computed rather than argued.** The
    /// tempting justification is that no verdict sits near the threshold — the
    /// nearest surviving pair clears one key width by 0.37 and the nearest
    /// dropped pair misses it by 0.57 — which is true and is still only a
    /// margin argument. The whole adjacency sweep was instead re-run at grid
    /// widths 360, 375, 390, 393, 402, 415, 430 and 440, covering the range of
    /// real iPhones: **the dropped list is the same fifteen pairs at every one
    /// of them, nothing is ever added, and `scale` stays exactly 1 throughout**,
    /// checked per row rather than assumed, so no row is ever squeezed out of
    /// the reference width this ratio is derived from.
    private static let gapRatio: Double = 4.0 / 36.0

    /// The leading Shift and trailing Backspace widths, in reference key units.
    private static let leadingPinnedKeyWidth: Double = 1.5
    private static let trailingPinnedKeyWidth: Double = 1.35

    /// The explicit 4pt visual nudge on Hebrew's top row, in reference key units.
    private static let hebrewTopRowOffset: Double = 4.0 / 36.0

    /// Ten reference columns and the nine gaps between them, in key widths.
    /// Matches `KeyboardLayout.referenceColumns`, which every letter row is
    /// centred against regardless of its own key count — English and Hebrew
    /// both need exactly ten (`KeyboardLayout.columns` floors there and
    /// neither layout needs more), so this is the one width both share.
    private static let referenceRowWidth: Double = 10 + 9 * gapRatio

    /// Two keys in neighbouring rows are adjacent when their footprints
    /// overlap. Every key is one key width wide, so two centres less than one
    /// key width apart share some of that width; two centres exactly one key
    /// width apart have touching edges and share none. That is the geometric
    /// floor, not a tuned number — it is the same test as asking whether two
    /// equal-width rectangles, placed at these two centres, touch.
    private static let adjacentThresholdKeyWidths: Double = 1

    /// A key's horizontal centre, in key widths, on a keyboard normalised to
    /// one key wide. Reproduces `KeyboardLayout.widths(for:)`'s own centring:
    /// a row's letters sit in whatever room is left between its pinned ends
    /// (if any), centred in that room exactly as SwiftUI centres a flexible
    /// `HStack` inside a fixed frame.
    private static func normalizedCenter(
        row: Int, col: Int, letters: [String], shapes: [RowShape]
    ) -> Double {
        let shape = shapes[row]
        let count = letters[row].count
        let leftBoundary = shape.leadingPinned ? leadingPinnedKeyWidth + gapRatio : 0
        let rightBoundary = shape.trailingPinned ? trailingPinnedKeyWidth + gapRatio : 0
        let offered = referenceRowWidth - leftBoundary - rightBoundary
        let content = Double(count) + Double(count - 1) * gapRatio
        let margin = max(0, (offered - content) / 2)
        let phase = leftBoundary + margin + 0.5
        return phase + Double(col) * (1 + gapRatio) + shape.horizontalOffset
    }
}
