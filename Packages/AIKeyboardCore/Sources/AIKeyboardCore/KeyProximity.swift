import Foundation

/// Whether two letters sit next to each other on the letter plane.
///
/// **Offers only.** A fat-finger substitution may climb inside the neighbour
/// tier; `shouldAutocorrect` still commits a same-length neighbour only when
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
        let letters = rows(for: language)
        guard let first = position(of: a, in: letters), let second = position(of: b, in: letters)
        else { return false }
        let rowGap = abs(first.row - second.row)
        if rowGap == 0 { return abs(first.col - second.col) == 1 }
        guard rowGap == 1 else { return false }
        let shapes = rowShapes(for: language, letters: letters)
        let centerA = normalizedCenter(row: first.row, col: first.col, letters: letters, shapes: shapes)
        let centerB = normalizedCenter(row: second.row, col: second.col, letters: letters, shapes: shapes)
        return abs(centerA - centerB) < adjacentThresholdKeyWidths
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
                trailingPinned: index == deleteRow)
        }
    }

    /// Gap between two keys in the same row, in key widths.
    ///
    /// **A measured ratio, not a geometric constant, and it is the one number
    /// in this file that is only exact on the device it was measured on.**
    /// `Theme.Metrics.keySpacing` is a fixed 6pt; the key width it is divided
    /// by grows with the screen, so this ratio shrinks a few percent on a
    /// wider phone and grows a few percent on a narrower one. iPhone 17 Pro:
    /// a 402pt-wide screen gives a 34.2pt reference key width, which is the
    /// same arithmetic `KeyboardLayout.pinnedWidth`'s own doc comment works
    /// out to 51.3pt at 1.5 units. None of the verdicts below are close to
    /// the 1-key-width threshold — the nearest surviving pair clears it by
    /// 0.16 of a key width and the nearest dropped pair misses it by 0.51 —
    /// so this ratio moving within the range of real iPhone widths does not
    /// flip anything reported in the file-level doc comment.
    private static let gapRatio: Double = 6.0 / 34.2

    /// Shift and delete, in key widths. Matches `KeyboardLayout.functionKeyUnits`.
    private static let pinnedKeyWidth: Double = 1.5

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
        let leftBoundary = shape.leadingPinned ? pinnedKeyWidth + gapRatio : 0
        let rightBoundary = shape.trailingPinned ? pinnedKeyWidth + gapRatio : 0
        let offered = referenceRowWidth - leftBoundary - rightBoundary
        let content = Double(count) + Double(count - 1) * gapRatio
        let margin = max(0, (offered - content) / 2)
        let phase = leftBoundary + margin + 0.5
        return phase + Double(col) * (1 + gapRatio)
    }
}
