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
/// `Match.coverage` is the closest thing the data has. Measured over 29 English
/// and Hebrew queries, the obvious answer comes back first for 22 and inside the
/// first five for 28, and the strip shows about nine at once. The remaining
/// spread is between emoji that all mean the right thing: `party` leads with 🪅
/// before 🎉, `cake` with 🥮 before 🍰. Tuning past this would be fitting one
/// person's taste to 1,870 rows.
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
        /// under six other vehicles. An exact keyword covers all of itself, and
        /// 3 of "police car"'s 10 characters is not a match of the same strength.
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
    /// generator, so no search folds 1,870 strings on its first keystroke, and
    /// CLDR's Hebrew carries no niqqud to strip.
    static func normalise(_ query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func score(needle: String, names: [String], keywords: String) -> Match {
        let keywordWords = keywords.split(separator: " ")
        var best = Match.none

        for name in names where name == needle {
            return Match(rung: 0, coverage: -1, length: name.count)
        }

        // An exact keyword and a whole word of a name are one rung. The keyword
        // covers all of itself and so wins the tie against a long name that merely
        // contains the word — see `Match.coverage`.
        if keywordWords.contains(where: { $0 == needle }) {
            best = min(best, Match(rung: 1, coverage: -1, length: shortest(names)))
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
