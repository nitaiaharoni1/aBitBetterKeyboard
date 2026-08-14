import Foundation

/// Whether two letters sit next to each other on the letter plane.
///
/// **Offers only.** A fat-finger substitution may climb inside the neighbour
/// tier; `shouldAutocorrect` still commits a same-length neighbour only when
/// `SeedLanguageModel.isTransposition` says so. The rows are written out
/// rather than read from `KeyboardLayout`, because the typing harness copies
/// this file and does not compile that one.
enum KeyProximity {

    static func rows(for language: KeyboardLanguage) -> [String] {
        if language == .hebrew {
            return ["קראטוןםפ", "שדגכעיחלךף", "זסבהנמצתץ"]
        }
        return ["qwertyuiop", "asdfghjkl", "zxcvbnm"]
    }

    /// Same row at col±1, or a neighbouring row at col±1 (diagonal included).
    static func areAdjacent(_ a: Character, _ b: Character, in language: KeyboardLanguage) -> Bool {
        let letters = rows(for: language)
        guard let first = position(of: a, in: letters), let second = position(of: b, in: letters)
        else { return false }
        let rowGap = abs(first.row - second.row)
        let colGap = abs(first.col - second.col)
        if rowGap == 0 { return colGap == 1 }
        if rowGap == 1 { return colGap <= 1 }
        return false
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
}
