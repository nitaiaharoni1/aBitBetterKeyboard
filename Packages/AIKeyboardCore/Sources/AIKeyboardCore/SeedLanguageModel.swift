import Foundation
import os

/// What the keyboard knows about a language on the day it is installed.
///
/// **The missing piece this fills is a frequency prior, and its absence was the
/// single biggest source of wrong slots.** `UITextChecker` answers "is this a
/// word" and "what words start like this", and it answers both without any sense
/// of which answer a person is more likely to have meant. So `helo` completed to
/// `helot` and `helots` — real words, which is why the correction branch never
/// ran — while `hello` was never offered at all, and `הכתו` completed to `הכתום`
/// ("the orange") ahead of `הכתובת` ("the address"). Rank is all it takes to
/// settle that class, and rank is all this claims.
///
/// **What the data is.** Hand-authored order, written by the author against the
/// kind of text this keyboard is typed into, and generated into
/// `Resources/LanguageModel.json` by `Scripts/generate-language-model.py`. It is
/// **not** measured against a corpus, and no count is stored — only position.
/// Disclosed in the resource itself under `source`, for the same reason the
/// typing corpus stamps `acceptableSource` on every hand-written list: a reader
/// who cannot tell an authored list from a measured one will trust it for things
/// it cannot support.
///
/// **It is a seed, not the model.** It exists to cold-start an install.
/// `PersonalLanguageModel` learns from the person using the keyboard and outranks
/// everything here, which is the part that actually makes the bar fit somebody.
///
/// **Two languages, and silence for the other twelve.** English and Hebrew are
/// the languages this list was written for. A Greek or Persian keyboard gets
/// `nil` from every call rather than English ranks under a Greek layout — the
/// same rule `nextWordTables` follows and for the same reason.
///
/// Hebrew is stored **bare**, without the clitics ‎ה ב ל מ ו ש כ‎;
/// `HebrewMorphology` strips one before asking and puts it back afterwards, so
/// one row for `עבודה` serves `לעבודה`, `בעבודה` and `מהעבודה`.
enum SeedLanguageModel {

    // MARK: Lookup

    /// Position in the frequency order, 0 being the most common. `nil` for a word
    /// the seed has never heard of, which is most words — the list is a prior over
    /// the common core, not a dictionary, and `UITextChecker` remains the
    /// authority on whether something is a word at all.
    static func rank(of word: String, in language: KeyboardLanguage) -> Int? {
        catalogue[language.languageTag]?.ranks[fold(word)]
    }

    static func knows(_ word: String, in language: KeyboardLanguage) -> Bool {
        rank(of: word, in: language) != nil
    }

    /// The whole seed list for a language, commonest first.
    ///
    /// Exists for `GroupedDecoder`, which has to *enumerate* a vocabulary rather
    /// than ask about one word: a grouped keystroke is a set of possible prefixes,
    /// and `UITextChecker` cannot be asked that question. This is the fallback it
    /// runs on when the generated resource is absent, and a few hundred words is
    /// exactly as thin as it sounds.
    static func allWords(in language: KeyboardLanguage) -> [String] {
        catalogue[language.languageTag]?.unigrams ?? []
    }

    /// Words that commonly follow the end of this sentence, most likely first.
    ///
    /// **Takes the last few words, not the last one, and tries the longest key
    /// first.** `you` is followed by half the language, so `See you ` answered
    /// `can`, `so`, `are` — all true of `you` and none of them what anybody
    /// writing "See you" is about to type. `see you` is followed by four words and
    /// they are the right four. The table stores both lengths under plain string
    /// keys, so a longer phrase costs a row and no new mechanism; the lookup walks
    /// from the longest suffix down and takes the first that answers.
    ///
    /// Small on purpose: it answers the handful of openings a chat keyboard sees
    /// constantly and answers nothing at all for the rest, rather than guessing.
    static func followers(after words: [String], in language: KeyboardLanguage) -> [String] {
        guard let bigrams = catalogue[language.languageTag]?.bigrams else { return [] }
        let tail = words.filter { !$0.isEmpty }.suffix(maximumKeyWords)
        for length in stride(from: tail.count, through: 1, by: -1) {
            let key = fold(tail.suffix(length).joined(separator: " "))
            if let hits = bigrams[key], !hits.isEmpty { return hits }
        }
        return []
    }

    /// Every collocation this token list can see, later windows first.
    ///
    /// `followers(after:)` only reads the last two words, so
    /// `Thanks for the quick turnaround. I'll send a` forgot `the quick` the
    /// moment two more words landed. Sliding a two-word window over the whole
    /// list is how the field, not just its tail, reaches the seed table.
    ///
    /// **One-word keys fire only at the end.** `the` is followed by half the
    /// language, and it appears in every English sentence; asking it of every
    /// token would mark `way` and `address` as "the sentence wanted this" for
    /// the rest of the message. A pair is specific enough to keep (`the quick`
    /// → `response`). The last token still gets its one-word row, which is
    /// what `followers(after:)` already returned.
    static func followers(mentionedIn words: [String], in language: KeyboardLanguage) -> [String] {
        guard let bigrams = catalogue[language.languageTag]?.bigrams else { return [] }
        let tokens = words.filter { !$0.isEmpty }.map(fold)
        guard !tokens.isEmpty else { return [] }
        var seen = Set<String>()
        var out: [String] = []
        for end in stride(from: tokens.count, through: 1, by: -1) {
            let maxLength = min(maximumKeyWords, end)
            let minLength = end == tokens.count ? 1 : 2
            for length in stride(from: maxLength, through: minLength, by: -1) {
                let key = tokens[(end - length)..<end].joined(separator: " ")
                guard let hits = bigrams[key] else { continue }
                for hit in hits where seen.insert(fold(hit)).inserted {
                    out.append(hit)
                }
            }
        }
        return out
    }

    /// The longest phrase the table is keyed on. Two: three-word keys were tried
    /// and every one of them was already answered by its own last two words, so
    /// they only cost rows.
    private static let maximumKeyWords = 2

    /// Seed words starting with this prefix, most common first.
    ///
    /// **A completion source in its own right, not only a ranker.** `UITextChecker`
    /// has never heard of `Wolt`, `Dizengoff` or `Herzliya`, so on the sentences
    /// this keyboard exists for it offered `Wolverine`, `Dizziness` and nothing.
    /// Those live in the same seed list as the ordinary words, so they arrive
    /// ranked alongside them instead of through a second mechanism.
    static func words(
        startingWith prefix: String, in language: KeyboardLanguage, limit: Int
    )
        -> [String]
    {
        guard let block = catalogue[language.languageTag] else { return [] }
        let folded = fold(prefix)
        guard !folded.isEmpty else { return [] }
        var out: [String] = []
        for (index, candidate) in block.folded.enumerated()
        where candidate.hasPrefix(folded) && candidate != folded {
            out.append(block.unigrams[index])
            if out.count == limit { break }
        }
        return out
    }

    /// Seed words one single-character edit away from this one, most common first.
    ///
    /// **The correction path `UITextChecker` does not cover in Hebrew.** `תדוה`
    /// for `תודה` is two adjacent letters swapped, the commonest slip there is,
    /// and the checker returns no guesses for it at all — so the bar showed the
    /// typo and nothing else. Restricted to distance 1 and to words already in
    /// the seed list, so it can only ever propose a *common* word, which is the
    /// property that keeps it from inventing corrections for rare ones.
    ///
    /// Damerau, not Levenshtein: a transposition is one edit, because on a
    /// keyboard it is one mistake. Plain Levenshtein scores `תדוה`→`תודה` as two
    /// and would rank it behind every single-substitution neighbour.
    static func neighbours(of word: String, in language: KeyboardLanguage, limit: Int) -> [String] {
        guard let block = catalogue[language.languageTag] else { return [] }
        let folded = Array(shapeFolded(fold(word)))
        guard folded.count >= 3 else { return [] }
        var out: [String] = []
        for (index, other) in block.shapeFolded.enumerated() {
            // **Never shorter than what was typed, and this rule is load-bearing.**
            // Every prefix is a word in progress, so a shorter neighbour is a
            // proposal to delete a letter the user has just deliberately pressed:
            // `מונ` on the way to `מונית` is one edit from `מון`, `מאו` on the way
            // to `מאוחר` is one edit from `או`. Allowing it turned four correct
            // Hebrew completions into corrections of half-typed words, which is
            // the exact behaviour people switch autocorrect off over. The typos
            // this is for — `תדוה`, `שלמו` — are the same length as the word they
            // meant, because a transposition does not change how many keys were
            // pressed.
            guard other.count >= folded.count, other.count - folded.count <= 1,
                other != folded
            else { continue }
            guard isOneEditApart(folded, other) else { continue }
            out.append(block.unigrams[index])
            if out.count == limit { break }
        }
        return out
    }

    /// A word with Hebrew's five final forms written as their ordinary shapes.
    ///
    /// **Used for measuring edit distance and nowhere else.** `שלמו` for `שלום` is
    /// one transposition — the reader sees two letters in the wrong order — but on
    /// the code points it is *two* substitutions, because swapping the mem out of
    /// last position also changes its shape from `ם` to `מ`. Without this fold the
    /// commonest Hebrew slip scores as distance 2 and is never offered.
    ///
    /// It must not leak into lookup: `knows` and `rank` have to keep telling
    /// `שלום` and `שלומ` apart, or the final-form correction has nothing to
    /// correct.
    private static func shapeFolded(_ word: String) -> String {
        guard word.contains(where: { ordinaryForms[$0] != nil }) else { return word }
        return String(word.map { ordinaryForms[$0] ?? $0 })
    }

    /// `HebrewMorphology.finalForms` inverted, built once. It used to be rebuilt
    /// inside `shapeFolded`, which the neighbour search calls per candidate.
    private static let ordinaryForms: [Character: Character] = HebrewMorphology.finalForms
        .reduce(into: [:]) { $0[$1.value] = $1.key }

    // MARK: Edit distance

    /// Whether two words are within one insertion, deletion, substitution or
    /// transposition of adjacent characters.
    ///
    /// Written as an early-exit walk rather than a distance matrix because it runs
    /// against every seed word on a keystroke: the answer is almost always "no"
    /// and the walk reaches it after one mismatch plus a tail compare, where a
    /// matrix would fill `n × m` cells to say the same thing.
    private static func isOneEditApart(_ lhs: [Character], _ rhs: [Character]) -> Bool {
        if lhs.count == rhs.count {
            var mismatch = -1
            for index in lhs.indices where lhs[index] != rhs[index] {
                if mismatch >= 0 {
                    // A second mismatch is allowed only when the two sit next to
                    // each other and swapping them reconciles both — and the rest
                    // of the word after them still has to match, or this would
                    // accept a transposition plus any number of later errors.
                    guard mismatch == index - 1, lhs[index] == rhs[mismatch],
                        lhs[mismatch] == rhs[index]
                    else { return false }
                    return lhs[(index + 1)...].elementsEqual(rhs[(index + 1)...])
                }
                mismatch = index
            }
            return mismatch >= 0
        }
        let (longer, shorter) = lhs.count > rhs.count ? (lhs, rhs) : (rhs, lhs)
        var offset = 0
        for index in shorter.indices {
            if longer[index + offset] != shorter[index] {
                guard offset == 0 else { return false }
                offset = 1
                if longer[index + offset] != shorter[index] { return false }
            }
        }
        return true
    }

    /// Same length, one adjacent swap, after folding Hebrew final forms.
    ///
    /// **The neighbour rule's commit half, not its offer half.** A substitution
    /// of the same length (`מכונ` / `נכון`) is a word still being typed. A
    /// transposition (`teh` / `the`, `תדוה` / `תודה`) is two keys swapped and is
    /// the slip space should still correct.
    static func isTransposition(_ word: String, of other: String) -> Bool {
        let lhs = Array(shapeFolded(fold(word)))
        let rhs = Array(shapeFolded(fold(other)))
        guard lhs.count == rhs.count, lhs.count >= 2 else { return false }
        var mismatch = -1
        for index in lhs.indices where lhs[index] != rhs[index] {
            if mismatch >= 0 {
                guard mismatch == index - 1, lhs[index] == rhs[mismatch],
                    lhs[mismatch] == rhs[index]
                else { return false }
                return lhs[(index + 1)...].elementsEqual(rhs[(index + 1)...])
            }
            mismatch = index
        }
        return false
    }

    // MARK: Loading

    private static let logger = Logger(
        subsystem: "com.nitai.aikeyboard", category: "SeedLanguageModel")

    /// One language's seed data, with the two derived forms the keystroke path
    /// needs already computed.
    ///
    /// **Precomputed because both of them were being rebuilt on every keystroke.**
    /// `words(startingWith:)` folded all 785 English unigrams — twice per word,
    /// once in the `where` clause and once in the comparison — and `neighbours`
    /// folded *and* shape-folded every one of them and built a five-entry
    /// dictionary per candidate on the way. That is thousands of string
    /// allocations per key press against a 20 ms budget for the whole keyboard,
    /// paid to recompute a constant. Folding once at load costs three arrays and
    /// a few hundred microseconds, once.
    private struct Block {
        let unigrams: [String]
        /// `fold(unigrams[i])`, index-aligned.
        let folded: [String]
        /// `shapeFolded(folded[i])` as characters, index-aligned. Only the
        /// neighbour search reads this, and only ever compares it against another
        /// shape-folded word.
        let shapeFolded: [[Character]]
        let ranks: [String: Int]
        let bigrams: [String: [String]]
    }

    private struct Payload: Decodable {
        struct Language: Decodable {
            let unigrams: [String]
            let bigrams: [String: [String]]
        }
        let languages: [String: Language]
    }

    /// Read once, on the first suggestion, and held for the life of the process.
    ///
    /// 24 KB of JSON rather than string literals in a Swift file, which is the
    /// call `EmojiCatalog` already made and for the same reason: literals are a
    /// compile cost paid on every build. Small enough that the lazy read is one
    /// blocking `Data(contentsOf:)` and not worth a background load — a keyboard
    /// extension is memory-capped, not latency-capped, on a file this size.
    private static let catalogue: [String: Block] = {
        guard let data = payloadData() else {
            #if !HARNESS
            logger.error("LanguageModel.json: resource missing or unreadable")
            #endif
            return [:]
        }
        do {
            let payload = try JSONDecoder().decode(Payload.self, from: data)
            return payload.languages.mapValues { language in
                let folded = language.unigrams.map(fold)
                var ranks: [String: Int] = [:]
                ranks.reserveCapacity(folded.count)
                for (index, word) in folded.enumerated() where ranks[word] == nil {
                    ranks[word] = index
                }
                return Block(
                    unigrams: language.unigrams,
                    folded: folded,
                    shapeFolded: folded.map { Array(shapeFolded($0)) },
                    ranks: ranks,
                    bigrams: language.bigrams.reduce(into: [:]) {
                        $0[fold($1.key)] = $1.value
                    })
            }
        } catch {
            logger.error(
                "LanguageModel.json: JSON decode failed — \(error.localizedDescription, privacy: .public)"
            )
            return [:]
        }
    }()

    private static func payloadData() -> Data? {
        #if HARNESS
        // `Bundle.module` is synthesised by SwiftPM and does not exist when
        // Bar/typing/harness/run.sh compiles these files loose against the
        // simulator SDK. The harness passes the path instead.
        guard let path = ProcessInfo.processInfo.environment["LANGUAGE_MODEL_JSON"] else {
            return nil
        }
        return try? Data(contentsOf: URL(fileURLWithPath: path))
        #else
        guard let url = Bundle.module.url(forResource: "LanguageModel", withExtension: "json")
        else { return nil }
        return try? Data(contentsOf: url)
        #endif
    }

    /// The form two spellings of one word share, for lookup only.
    ///
    /// Lower case, NFC, and the Hebrew maqaf folded onto the ASCII hyphen — the
    /// same three moves `SuggestionEngine.comparable` makes, for the same reason:
    /// a Hebrew layout can only type the ASCII hyphen, so an entry spelled with
    /// Hebrew's own would otherwise be unreachable by the person who owns it.
    static func fold(_ word: String) -> String {
        word.precomposedStringWithCanonicalMapping.lowercased()
            .replacingOccurrences(of: "־", with: "-")
            .replacingOccurrences(of: "’", with: "'")
    }
}
