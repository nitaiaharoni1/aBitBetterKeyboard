import Foundation

/// Finding an emoji by typing a word, in either language the keyboard types.
///
/// **Ranking is the feature, not matching.** Almost every heart in Unicode
/// carries "heart" among its CLDR keywords and almost every one carries "לב", so
/// a filter that asks "does this emoji know that word" answers `heart` with 💘 and
/// `לב` with 🥰 — both true, neither what anybody meant. What follows is the
/// ordering, and every rung of it is here because a flatter version got something
/// visibly wrong against the real catalogue.
///
/// **What this cannot do, said plainly.** CLDR carries no frequency and no "this
/// is *the* emoji for this word", so there is no centrality signal to sort by —
/// `Match.coverage` is the closest thing the data has. Measured over
/// `Bar/emoji/corpus.json`, 99 frozen queries in both languages: the judged
/// answer comes back first for 58 of the 76 entries that can fail and inside the
/// first five for 70. The remaining spread is mostly between emoji that all mean
/// the right thing: `party` leads with 🪅 before 🎉, `cake` with 🥮 before 🍰.
/// Tuning past what that corpus can distinguish would be fitting one person's
/// taste to 1,870 rows.
///
/// **Hebrew morphology is the real gap.** Matching is by whole word and by
/// prefix, so `בוכה` finds 😭 and `בכי` — the same root, a different form — finds
/// nothing. Fixing it needs a stemmer this package does not have and cannot cheaply
/// get.
public enum EmojiSearch {

    /// How well one emoji answers a query. Smaller sorts first.
    struct Match: Comparable {
        /// 0 the query *is* a name, 1 it is a whole word of one or an exact
        /// keyword, 2 it starts a word of a name, 3 it starts a keyword.
        var rung: Int
        /// How much of the matched name the query accounts for, negated so that
        /// more coverage sorts first. **This is what puts the actual car first.**
        /// CLDR names 🚗 "automobile", so no name rung reaches it for `car` at all
        /// — while "police car" and "tram car" reach it on the name and buried it
        /// under six other vehicles. 3 of "police car"'s 10 characters is not a
        /// match of the same strength as a keyword that *is* the query, which is
        /// what `exactKeywordCoverage` prices.
        var coverage: Double
        /// Length of the name that earned the rung. The tiebreak of last resort
        /// before catalogue order, on the reasoning that "red heart" is a better
        /// answer to `heart` than "heart with ribbon" is.
        ///
        /// **Measured against the matched name, never the shortest one.** Taking
        /// the shortest across both locales compared an English query to a Hebrew
        /// name: ♥️'s "קלף לב" is shorter than ❤️'s "לב אדום", so `heart` answered
        /// with the card suit.
        var length: Int

        static let none = Match(rung: .max, coverage: 0, length: .max)

        static func < (a: Match, b: Match) -> Bool {
            if a.rung != b.rung { return a.rung < b.rung }
            if a.coverage != b.coverage { return a.coverage < b.coverage }
            return a.length < b.length
        }
    }

    /// An emoji the user has reached for before is a better guess than one they
    /// have not, so being in `recent` is worth two rungs. Bounded rather than
    /// absolute: a recent keyword-prefix match still loses to a fresh emoji whose
    /// *name* is the query, which is what stops `pizza` answering 😂.
    static let recentBoost = 2

    /// What an exact keyword is worth on rung 1, in `Match.coverage`'s own units:
    /// a keyword ranks as a name word filling exactly half of its name.
    ///
    /// **It used to be −1, which no name word can reach**, so an exact keyword
    /// always beat a name merely containing the word. That single value is what
    /// put 🏠 second for `heart`: CLDR lists `heart` among the house's keywords,
    /// and ❤️ — whose name *is* "red heart" — could not overtake it at any length.
    ///
    /// **Zero, the obvious repair, is worse, and that is measured rather than
    /// argued.** Letting a name word beat an exact keyword outright is +4 on
    /// `Bar/emoji`'s `first` and does fix `heart`, and it costs `ירח` rank 1 → 13
    /// and `car` 6 → 12, because "ירח מלא" and "police car" carry the word in a
    /// name where 🌙 and 🚗 only ever had it as a keyword. Hebrew is the language
    /// this keyboard exists for; a headline that rises while it falls is not a
    /// repair. `Bar/emoji/harness/variants.py` holds both, and three others.
    ///
    /// Half is the threshold where a name word is more of its name than not.
    /// "red heart" is 5 of 9 and clears it, which takes `heart` from rank 10 to
    /// rank 1; "new moon" is 4 of 8 and does not, so `moon` still answers 🌙.
    /// Over the 99-query corpus exactly three entries move and all three move
    /// forwards — `heart`, `money` and `apple`, each to rank 1 — for +2 on
    /// `first`, +1 on `strip` and +0.018 MRR, with nothing that answered at rank
    /// 1 losing the place.
    static let exactKeywordCoverage = -0.5

    /// Emoji for a query, best first.
    public static func results(
        for query: String, recent: [String] = [], limit: Int = 60
    )
        -> [String]
    {
        let needle = normalise(query)
        guard !needle.isEmpty else { return [] }

        var recentRank: [String: Int] = [:]
        for (index, emoji) in recent.enumerated() { recentRank[emoji] = index }

        var scored: [(emoji: String, match: Match, recent: Int, order: Int)] = []
        for emoji in EmojiCatalog.all {
            var match = score(
                needle: needle,
                names: EmojiCatalog.names(for: emoji),
                keywords: EmojiCatalog.keywords(for: emoji))
            guard match != .none else { continue }
            let rank = recentRank[emoji] ?? Int.max
            if rank != Int.max { match.rung = max(0, match.rung - recentBoost) }
            scored.append(
                (emoji: emoji, match: match, recent: rank, order: EmojiCatalog.order(of: emoji)))
        }

        scored.sort { a, b in
            if a.match.rung != b.match.rung { return a.match.rung < b.match.rung }
            if a.recent != b.recent { return a.recent < b.recent }
            if a.match != b.match { return a.match < b.match }
            return a.order < b.order
        }
        return scored.prefix(limit).map(\.emoji)
    }

    /// Lowercased and trimmed. Nothing else: the catalogue is lowercased by the
    /// generator, so no search folds 1,870 strings on its first keystroke.
    ///
    /// **Niqqud is not stripped, and CLDR's Hebrew does carry it** — in exactly
    /// four places: 🐏 is `אַיִל`, 🛷 is `מִזְחֶלֶת`, 👩‍🏫 is `מוֹרָה`, and 🩺 has
    /// `מַסְכֵּת` among its keywords. That is load-bearing rather than trivia,
    /// because every comparison below works on grapheme clusters:
    /// `"אַיִל".hasPrefix("א")` is **false**, since the first `Character` is alef
    /// *with* its patah. `Bar/emoji`'s Python port used code points, got 🐏's
    /// results wrong on that one string, and `swift-check.sh` is what caught it.
    ///
    /// **Folding them was measured and is not worth it.** Stripping here alone
    /// would achieve nothing — the catalogue side keeps its marks, so the two
    /// still never meet — and folding both sides leaves the corpus byte-identical
    /// at 56/76 first, 69/76 strip, 0.819 MRR. Three of the four are already
    /// reachable unpointed, because CLDR carries the bare spelling as a keyword
    /// even where the name is pointed: `איל` answers 🐏 first, `מזחלת` answers 🛷
    /// first, `מורה` answers 👩‍🏫 second. The entire gain is `מסכת` reaching 🩺,
    /// against folding 1,870 strings per keystroke unless `EmojiCatalog` folds
    /// them once at load.
    static func normalise(_ query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func score(needle: String, names: [String], keywords: String) -> Match {
        let keywordWords = keywords.split(separator: " ")
        var best = Match.none

        for name in names where name == needle {
            return Match(rung: 0, coverage: -1, length: name.count)
        }

        // An exact keyword and a whole word of a name are one rung, and
        // `exactKeywordCoverage` is where the two meet: a name word wins when the
        // query is more than half of the name, and loses when it is less. At
        // exactly half they tie and `length` settles it, the same way it settles
        // every other draw on this rung.
        if keywordWords.contains(where: { $0 == needle }) {
            best = min(
                best, Match(rung: 1, coverage: exactKeywordCoverage, length: shortest(names)))
        }
        for name in names where name.split(separator: " ").contains(where: { $0 == needle }) {
            best = min(best, Match(rung: 1, coverage: coverage(needle, name.count), length: name.count))
        }
        if best.rung <= 1 { return best }

        for name in names {
            for word in name.split(separator: " ") where word.hasPrefix(needle) {
                best = min(
                    best, Match(rung: 2, coverage: coverage(needle, name.count), length: name.count))
            }
        }
        for word in keywordWords where word.hasPrefix(needle) {
            best = min(
                best, Match(rung: 3, coverage: coverage(needle, word.count), length: word.count))
        }
        return best
    }

    private static func coverage(_ needle: String, _ length: Int) -> Double {
        length > 0 ? -Double(needle.count) / Double(length) : 0
    }

    private static func shortest(_ names: [String]) -> Int {
        names.map(\.count).min() ?? Int.max
    }
}
