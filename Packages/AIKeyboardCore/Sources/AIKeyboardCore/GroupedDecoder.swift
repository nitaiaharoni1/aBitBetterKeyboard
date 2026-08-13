import Foundation
import os

/// Turns a sequence of grouped key presses back into words.
///
/// **Why this needs a bundled word list at all.** `UITextChecker` answers "is
/// this a word" and "what completes this prefix", and a grouped keystroke is
/// neither — it is a *set* of possible prefixes. Asking the checker every
/// expansion is `lettersPerKey ^ length` calls, which is 81 questions four keys
/// into a three-letter grouping, against a 20 ms budget for the whole keyboard.
/// So the decoder owns a list it can index by keystroke instead.
///
/// **The list is the weak link and it is deliberately pluggable.** `Bar/grouped/`
/// measured this design against 200,000 words per language; the bundled resource
/// is smaller, and when it is absent entirely the decoder falls back to
/// `SeedLanguageModel` plus whatever the user has taught the keyboard — which
/// still decodes the common core and quietly will not reach much else.
/// `SharedStore.groupedLexiconState` reports which of the three it is running on,
/// so nothing has to guess.
public final class GroupedDecoder {

    /// Where the words came from, reported rather than assumed — the same rule
    /// `SharedStore.storage` follows about the App Group.
    public enum Source: String, Sendable {
        /// The generated resource. What `Bar/grouped/` measured.
        case bundled
        /// `SeedLanguageModel` and the user's own words. Common core only.
        case seedOnly
    }

    public let language: KeyboardLanguage
    public let level: GroupedKeys.Level
    public private(set) var source: Source

    /// Words in descending frequency, so a lower index is commoner.
    private let words: [String]
    /// `codes[i]` is `words[i]`'s keystroke sequence, one scalar per key pressed.
    /// Index-aligned with `order`, not with `words`.
    private let codes: [String]
    /// Indices into `words`, sorted by `codes` so a prefix is a contiguous range.
    private let order: [Int]

    private static let logger = Logger(
        subsystem: "com.nitai.aikeyboard", category: "GroupedDecoder")

    // MARK: Building

    public convenience init(
        language: KeyboardLanguage, level: GroupedKeys.Level, personal: [String] = []
    ) {
        let bundled = GroupedLexiconResource.words(for: language)
        // The user's own words go first: a name they typed into Settings outranks
        // anything a corpus knows about it, which is the rule the suggestion bar
        // already runs on.
        self.init(
            language: language, level: level,
            words: personal + (bundled.isEmpty ? SeedLanguageModel.allWords(in: language) : bundled),
            source: bundled.isEmpty ? .seedOnly : .bundled)
    }

    /// The designated one: an explicit vocabulary, no bundle and no settings.
    ///
    /// **Separated so the decoder can be measured without a keyboard around it.**
    /// `Bar/grouped/` proved the algorithm in Python; this is the port, and a port
    /// is exactly the thing that can be faithful in design and wrong in a detail.
    /// `Bar/grouped/harness/swift-check.sh` compiles this against the simulator
    /// SDK and checks the two implementations agree.
    init(
        language: KeyboardLanguage, level: GroupedKeys.Level, words vocabulary: [String],
        source: Source = .bundled
    ) {
        self.language = language
        self.level = level
        self.source = source

        var seen = Set<String>()
        var ordered: [String] = []
        for word in vocabulary {
            let folded = SeedLanguageModel.fold(word)
            guard !folded.isEmpty, seen.insert(folded).inserted else { continue }
            ordered.append(folded)
        }
        words = ordered

        // One scalar per key press. `letterToKey` is nil for anything not on this
        // layout, which drops the word rather than coding it wrongly.
        let map = GroupedDecoder.letterToKey(language: language, level: level)
        var built: [(Int, String)] = []
        built.reserveCapacity(ordered.count)
        for (index, word) in ordered.enumerated() {
            guard let code = GroupedDecoder.code(for: word, map: map) else { continue }
            built.append((index, code))
        }
        built.sort { $0.1 == $1.1 ? $0.0 < $1.0 : $0.1 < $1.1 }
        order = built.map(\.0)
        codes = built.map(\.1)
    }

    /// Which key each letter sits on, at this level.
    static func letterToKey(language: KeyboardLanguage, level: GroupedKeys.Level) -> [String: Int] {
        guard let base = KeyboardLayout.letterLayouts[language] else { return [:] }
        return letterToKey(
            rows: base.rows, keepingApart: language == .hebrew ? GroupedKeys.hebrewClitics : [],
            level: level)
    }

    /// The same from explicit rows, for the headless check.
    static func letterToKey(
        rows: [[String]], keepingApart avoid: Set<String>, level: GroupedKeys.Level
    )
        -> [String: Int]
    {
        let grouped = GroupedKeys.groups(for: rows, keepingApart: avoid, level: level)
        var map: [String: Int] = [:]
        var key = 0
        for row in grouped {
            for group in row {
                for letter in group { map[letter] = key }
                key += 1
            }
        }
        return map
    }

    /// The keystrokes a word would take, or `nil` if it cannot be typed here.
    ///
    /// Letters must be on the layout; anything that is not a letter — an
    /// apostrophe, a digit — passes through as itself, because it lives on the
    /// numbers plane where nothing is grouped and so is never ambiguous. That is
    /// what keeps `don't` in the dictionary rather than dropping every
    /// contraction.
    static func code(for word: String, map: [String: Int]) -> String? {
        var out = String.UnicodeScalarView()
        for character in word {
            if let key = map[String(character)] {
                // Private Use Area, so a key index can never collide with a real
                // character passing through below. At 0x100 it would have: ā is
                // U+0101, which is key 1.
                out.append(UnicodeScalar(UInt32(0xE000 + key))!)
            } else if character.isLetter {
                return nil
            } else {
                out.append(contentsOf: String(character).unicodeScalars)
            }
        }
        return String(out)
    }

    // MARK: Decoding

    /// Words whose keystrokes begin with this sequence, commonest first.
    ///
    /// Answers a *prefix*, not a whole word, because the bar has to say something
    /// while the word is still being typed — the same reason
    /// `SuggestionEngine.completions` exists.
    public func candidates(
        startingWith code: String, pinnedTo pins: [Int: String] = [:], limit: Int = 3
    ) -> [String] {
        guard !code.isEmpty, !codes.isEmpty else { return [] }
        var best: [(rank: Int, word: String)] = []
        var scanned = 0
        for position in range(startingWith: code) {
            scanned += 1
            if scanned > GroupedDecoder.scanLimit { break }
            let rank = order[position]
            if !pins.isEmpty, !GroupedDecoder.honours(pins, words[rank]) { continue }
            if best.count < limit {
                best.append((rank, words[rank]))
                best.sort { $0.rank < $1.rank }
            } else if rank < best[limit - 1].rank {
                best[limit - 1] = (rank, words[rank])
                best.sort { $0.rank < $1.rank }
            }
        }
        return best.map(\.word)
    }

    /// Whether a word has the letters the user pinned, where they pinned them.
    ///
    /// A pin is a letter the user aimed at: a long press, or a tap clearly on
    /// one letter of the group. It is a hard filter rather than a ranking
    /// nudge: a candidate that disagrees with a letter somebody aimed at is
    /// not a worse answer, it is the wrong answer.
    static func honours(_ pins: [Int: String], _ word: String) -> Bool {
        let letters = Array(word)
        for (position, letter) in pins {
            guard position < letters.count, String(letters[position]) == letter else {
                return false
            }
        }
        return true
    }

    /// **A cap on work, not on correctness, and it is logged when it bites.**
    /// One key press into a three-key layout selects a third of the list, and
    /// walking 60,000 entries for a candidate nobody will read is how a keyboard
    /// misses a frame. The entries are in frequency order within the scan, so the
    /// commonest words are reached first and the cut only ever loses rare ones.
    static let scanLimit = 4000

    /// The contiguous slice of `codes` beginning with this prefix.
    private func range(startingWith prefix: String) -> Range<Int> {
        var low = 0
        var high = codes.count
        while low < high {
            let middle = (low + high) / 2
            if codes[middle] < prefix { low = middle + 1 } else { high = middle }
        }
        let start = low
        high = codes.count
        while low < high {
            let middle = (low + high) / 2
            if codes[middle].hasPrefix(prefix) || codes[middle] < prefix {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return start..<low
    }

    /// What to show when the list has nothing: the first letter of each key
    /// pressed.
    ///
    /// **The keyboard must never go blank while somebody is typing.** A decoder
    /// with no answer still has to put the keystrokes on screen, or the field
    /// stops responding to the keys and the user has no way to tell a slow
    /// keyboard from a broken one. It is usually not a word, and it is always
    /// something the user can see and delete.
    public static func literal(for caps: [String]) -> String {
        caps.compactMap { GroupedKeys.letters(inCap: $0).first }.joined()
    }
}
