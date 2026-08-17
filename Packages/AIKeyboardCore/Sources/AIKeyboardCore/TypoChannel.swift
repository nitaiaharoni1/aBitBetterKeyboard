import Foundation

/// A weighted Damerau-Levenshtein cost between what somebody typed and a word
/// they might have meant.
///
/// **Why edit distance 1 was not enough.** `דוגמטןת` for `דוגמאות` ("examples")
/// is two adjacent-key substitutions — `א`↔`ט` and `ו`↔`ן` sit side by side on
/// the Hebrew layout's top row — and every correction source in this engine
/// before this file (`SeedLanguageModel.neighbours`, `UITextChecker.guesses`) is
/// bounded at distance 1, so none of them could reach it. Plain Levenshtein
/// distance 2 is not the fix either: it would rank a wild two-letter swap
/// exactly level with two adjacent-key slips, and a keyboard's job is to tell
/// those apart. Every cost below is relative to `plainEdit`, an arbitrary
/// unweighted substitution, so "how much cheaper is a fat-finger slip than a
/// wild guess" is a ratio anybody reading this can check against the numbers.
///
/// **Costs are asymmetric between insertion and deletion on purpose.** A
/// missing letter (the candidate has one the typed word does not) and a stray
/// letter (the typed word has one the candidate does not) sound like mirror
/// images, but they are not the same mistake: a doubled letter typed once is
/// "I pressed one key where the word needs two," and a doubled letter typed
/// twice is "I pressed one key twice by accident." Both are cheap, but the
/// tables that decide *which* letter drop or add is cheap are built
/// independently, and `cost(typed:candidate:)` is therefore not
/// `cost(typed:candidate:) == cost(typed: candidate, candidate: typed)` in
/// general — only the substitution and transposition rules are inherently
/// symmetric, because they compare a pair of letters rather than one letter
/// against its neighbours.
enum TypoChannel {

    /// One ordinary edit, with no rule behind it. Every other cost in this file
    /// is written as a fraction or a multiple of this, so the comment beside
    /// each number can say "cheaper than a wild guess" and mean something
    /// specific.
    static let plainEdit = 100

    /// The cheapest an insertion or a deletion can ever cost. Nothing here is
    /// measured against a corpus; it is the floor read straight off the tables
    /// below (55, in both directions), and it is what "how many edits can this
    /// budget afford" has to be computed from rather than assumed. `TypoLexicon`
    /// reads it too, so the two files cannot silently disagree about the bound.
    static let minimumIndelCost = 55

    /// What a word of this length is allowed to spend correcting itself.
    ///
    /// **The gate exists so the corrector cannot rewrite a word still being
    /// typed.** At three letters, two cheap edits (`110`, the case this file
    /// was built for) is most of the word, so the corrector must not run at
    /// all — `nil` says that plainly rather than returning a huge, useless
    /// budget. Four and five letters get exactly one ordinary edit or two very
    /// cheap ones (`100`); six and up get enough for the two-adjacent-slip case
    /// that started this (`55 + 55 = 110`) with headroom, but not enough for two
    /// *unrelated* substitutions (`100 + 100 = 200`), which is deliberate: a
    /// word two wild guesses away from the keystrokes is not a typo of it.
    static func budget(forTypedLength length: Int) -> Int? {
        switch length {
        case ..<4: return nil
        case 4...5: return plainEdit
        default: return 130
        }
    }

    /// The cost of the cheapest sequence of slips that turns `candidate` into
    /// `typed`, or `nil` when nothing that cheap exists.
    ///
    /// **Banded, not a full matrix, and that is a requirement rather than a
    /// style choice.** This runs against thousands of candidate words on a
    /// single keystroke, inside a keyboard extension with about 20 ms for
    /// everything it does that turn. A full `candidate.count × typed.count`
    /// matrix is `O(n·m)` in both time and memory per call and pays for
    /// alignments the budget could never afford anyway — a two-letter word and
    /// an eleven-letter word are never eleven edits apart within any budget
    /// this file hands out. Only an insertion or a deletion moves the
    /// diagonal offset `d = j - i` away from zero, and the cheapest either one
    /// can ever cost is `minimumIndelCost`, so a cell whose offset is more than
    /// `budget / minimumIndelCost` away from zero cannot be reached inside
    /// budget by any path, cheap or not — filling it is wasted work. The DP
    /// below only ever visits offsets in that band, and it rolls three rows
    /// (the current one, the one before it, and the one before that) rather
    /// than allocating a matrix. Three rather than the classic two because
    /// this is Damerau, not plain Levenshtein: a transposition reaches back to
    /// `(i-2, j-2)`, one row further than a substitution.
    ///
    /// Returns early, mid-computation, the moment an entire row's cheapest
    /// cell already exceeds `budget`: every remaining operation only adds
    /// non-negative cost, so once a row cannot afford the budget, no row after
    /// it can either.
    static func cost(
        typed rawTyped: [Character], candidate rawCandidate: [Character],
        language: KeyboardLanguage, budget: Int
    ) -> Int? {
        let typed = rawTyped.map(fold)
        let candidate = rawCandidate.map(fold)
        let typedCount = typed.count
        let candidateCount = candidate.count

        let band = max(0, budget / minimumIndelCost)
        guard abs(candidateCount - typedCount) <= band else { return nil }

        // Each letter's insertion or deletion cost depends only on its own
        // neighbours inside its own word, never on where the DP path happens
        // to cross it — so both tables are computed once, up front, rather
        // than recomputed inside the O(band · n) loop below.
        let insertionCostAt: [Int] = (0..<typedCount).map { index in
            insertionCost(
                typed[index], leftNeighbor: index >= 1 ? typed[index - 1] : nil,
                rightNeighbor: index + 1 < typedCount ? typed[index + 1] : nil, language: language)
        }
        let deletionCostAt: [Int] = (0..<candidateCount).map { index in
            deletionCost(
                candidate[index], leftNeighbor: index >= 1 ? candidate[index - 1] : nil,
                rightNeighbor: index + 1 < candidateCount ? candidate[index + 1] : nil,
                isTrailing: index == candidateCount - 1, language: language)
        }

        let unreachable = Int.max / 2
        let width = 2 * band + 1
        // Row `i` is stored indexed by `d + band`, where `d = j - i`, so every
        // row uses the same fixed-width array regardless of how far into the
        // word it is — the diagonal a row is centred on shifts with `i`, the
        // storage does not.
        var rowBeforeLast = [Int](repeating: unreachable, count: width)
        var previousRow = [Int](repeating: unreachable, count: width)
        var currentRow = [Int](repeating: unreachable, count: width)

        // Row 0: turning the empty candidate prefix into `typed[0..<j]` is
        // nothing but insertions.
        var running = 0
        for d in 0...band {
            guard d <= typedCount else { break }
            if d == 0 {
                previousRow[band] = 0
            } else {
                running += insertionCostAt[d - 1]
                previousRow[d + band] = running
            }
        }

        if candidateCount >= 1 {
            for i in 1...candidateCount {
                for k in 0..<width { currentRow[k] = unreachable }
                let dMin = max(-band, -i)
                let dMax = min(band, typedCount - i)
                guard dMin <= dMax else { return nil }

                for d in dMin...dMax {
                    let j = i + d
                    var best = unreachable

                    // Deletion: from (i-1, j), one row up, offset shifts to d+1.
                    let deletionOffset = d + 1
                    if deletionOffset <= band {
                        let candidateCost = previousRow[deletionOffset + band]
                        if candidateCost < unreachable {
                            best = min(best, candidateCost + deletionCostAt[i - 1])
                        }
                    }

                    if j >= 1 {
                        // Insertion: from (i, j-1), same row, offset shifts to d-1.
                        let insertionOffset = d - 1
                        if insertionOffset >= -band {
                            let candidateCost = currentRow[insertionOffset + band]
                            if candidateCost < unreachable {
                                best = min(best, candidateCost + insertionCostAt[j - 1])
                            }
                        }

                        // Substitution (or a match, at cost 0): from (i-1, j-1),
                        // one row up, same offset.
                        let diagonalCost = previousRow[d + band]
                        if diagonalCost < unreachable {
                            best = min(
                                best,
                                diagonalCost
                                    + substitutionCost(candidate[i - 1], typed[j - 1], language: language)
                            )
                        }
                    }

                    // Transposition: from (i-2, j-2), two rows up, same offset —
                    // the two letters that swapped are still both inside the
                    // band because a transposition never moves the diagonal.
                    //
                    // **Checked twice, cheap first.** Swapping a letter across
                    // Hebrew's word-final boundary changes its shape along
                    // with its position — `שלמו` for `שלום` moves `ם` out of
                    // final position, where it must be written `מ`, so on the
                    // code points the swap is `ו`↔`מ` and `ם`↔`ו`, not the
                    // clean two-letter swap the raw check below is written to
                    // find. The raw check is tried first because it is what a
                    // transposition looks like whenever neither letter
                    // crosses that boundary, and it is strictly cheaper when
                    // it matches. Only when it fails is the same pair tried
                    // again against `shapeFold`, at `transpositionCost + 20`
                    // — the same 20 `substitutionCost` already charges for a
                    // final-form pair, because that is exactly the extra
                    // difference a shape change costs on top of the swap
                    // itself.
                    if i >= 2, j >= 2 {
                        let candidateCost = rowBeforeLast[d + band]
                        if candidateCost < unreachable {
                            if candidate[i - 1] == typed[j - 2], candidate[i - 2] == typed[j - 1] {
                                best = min(best, candidateCost + transpositionCost)
                            } else if shapeFold(candidate[i - 1]) == shapeFold(typed[j - 2]),
                                shapeFold(candidate[i - 2]) == shapeFold(typed[j - 1])
                            {
                                best = min(best, candidateCost + transpositionCost + 20)
                            }
                        }
                    }

                    currentRow[d + band] = best
                }

                let rowMinimum = (dMin...dMax).map { currentRow[$0 + band] }.min() ?? unreachable
                if rowMinimum > budget { return nil }

                rowBeforeLast = previousRow
                previousRow = currentRow
            }
        }

        let finalOffset = typedCount - candidateCount
        let result = previousRow[finalOffset + band]
        guard result < unreachable, result <= budget else { return nil }
        return result
    }

    // MARK: Substitution

    /// Every rule here is symmetric in its two letters — equality, a
    /// final-form pair, a confusion class and `KeyProximity.areAdjacent` all
    /// answer the same question whichever letter is "the candidate's" and
    /// which is "what was typed" — so `substitutionCost(a, b)` always equals
    /// `substitutionCost(b, a)`, unlike the insertion and deletion tables.
    private static func substitutionCost(
        _ a: Character, _ b: Character, language: KeyboardLanguage
    )
        -> Int
    {
        if a == b { return 0 }
        if finalFormPartner[a] == b { return 20 }
        if inConfusionClass(a, b, in: language) { return 40 }
        if KeyProximity.areAdjacent(a, b, in: language) { return 55 }
        return plainEdit
    }

    /// `HebrewMorphology.finalForms` inverted and combined, so either shape of
    /// a letter maps to its partner. Built once rather than per comparison,
    /// the same reason `SeedLanguageModel.ordinaryForms` exists.
    private static let finalFormPartner: [Character: Character] = HebrewMorphology.finalForms
        .reduce(into: [:]) {
            $0[$1.key] = $1.value
            $0[$1.value] = $1.key
        }

    /// A letter with its final form folded onto its ordinary shape, and every
    /// other letter unchanged.
    ///
    /// **One direction only, and that is what makes it useful for the
    /// transposition check.** `HebrewMorphology.finalForms` inverted — the
    /// same construction `SeedLanguageModel.ordinaryForms` uses privately for
    /// its own shape-folded comparison — because "did this letter's shape
    /// change" is answered by folding *to* the ordinary form and comparing,
    /// not by a symmetric partner lookup like `finalFormPartner`, which would
    /// answer yes for two letters that are simply different.
    private static let ordinaryForms: [Character: Character] = HebrewMorphology.finalForms
        .reduce(into: [:]) { $0[$1.value] = $1.key }

    private static func shapeFold(_ character: Character) -> Character {
        ordinaryForms[character] ?? character
    }

    /// Letters that sound alike, and so are typed for one another, in each
    /// script this keyboard supports.
    ///
    /// **Hebrew's classes are phonetic, not visual** — the letters modern
    /// Israeli Hebrew pronounces the same way, which is what actually drives a
    /// misspelling: `א`/`ה`/`ע` are all silent or near-silent, `ח`/`כ` and
    /// `ט`/`ת` and `ב`/`ו` and `ס`/`ש` are pairs a speaker cannot hear apart.
    /// English's are the vowels, which are interchangeable enough in casual
    /// typing to be one class, plus letter pairs that spell the same sound
    /// two ways (`c`/`k`, `c`/`s`, `s`/`z`) or are easy to swap by hand
    /// (`i`/`y`, `f`/`v`, `g`/`j`). These are the pairs named in the design;
    /// nothing here is measured against a corpus, and a class that turns out
    /// to fire on real typos it should not is a corpus question, not a
    /// guess to pre-empt.
    private static let hebrewConfusionClasses: [Set<Character>] = [
        ["א", "ה", "ע"], ["ח", "כ"], ["ט", "ת"], ["כ", "ק"], ["ב", "ו"], ["ס", "ש"]
    ]

    private static let englishConfusionClasses: [Set<Character>] = [
        ["a", "e", "i", "o", "u", "y"], ["c", "k"], ["c", "s"], ["s", "z"], ["i", "y"], ["f", "v"],
        ["g", "j"]
    ]

    private static func inConfusionClass(
        _ a: Character, _ b: Character, in language: KeyboardLanguage
    )
        -> Bool
    {
        let classes = language == .hebrew ? hebrewConfusionClasses : englishConfusionClasses
        return classes.contains { $0.contains(a) && $0.contains(b) }
    }

    // MARK: Deletion — the candidate has a letter the typed word does not

    /// **Why this is not symmetric with insertion.** The three deletion rules
    /// (a mater lectionis, a doubled letter, a trailing silent `e`) are all
    /// about what the *candidate* — the real word — legitimately contains that
    /// a hurried typist skips. They say nothing about what makes a *stray*
    /// keystroke likely, which is a different question with its own table
    /// below.
    private static func deletionCost(
        _ missing: Character, leftNeighbor: Character?, rightNeighbor: Character?, isTrailing: Bool,
        language: KeyboardLanguage
    ) -> Int {
        // Hebrew is written both with and without its matres lectionis (ktiv
        // male vs ktiv haser), and dropping one is the single commonest
        // Hebrew misspelling: דוגמאות/דוגמות, אמיתי/אמתי. This is the rule
        // that makes `דוגמות` → `דוגמאות` a 55, not a 100.
        if language == .hebrew, isMaterLectionis(missing) { return 55 }
        // A doubled letter typed once — `acommodate` for `accommodate` — reads
        // as one keystroke where the word needs two, which is cheap to make
        // and cheap to reverse. Checked on both sides because either
        // occurrence of the pair could be "the one that's missing."
        if missing == leftNeighbor || missing == rightNeighbor { return 55 }
        // English's trailing silent `e` is dropped by exactly the same
        // instinct as a doubled letter: the ear does not hear it, so a fast
        // typist does not type it.
        if language == .english, missing == "e", isTrailing { return 55 }
        return plainEdit
    }

    private static func isMaterLectionis(_ letter: Character) -> Bool {
        letter == "י" || letter == "ו" || letter == "א"
    }

    // MARK: Insertion — the typed word has a letter the candidate does not

    private static func insertionCost(
        _ extra: Character, leftNeighbor: Character?, rightNeighbor: Character?,
        language: KeyboardLanguage
    ) -> Int {
        // The same over-writing of a mater lectionis, the other way: a typist
        // who writes ktiv male where the stored form is ktiv haser has added
        // a letter the dictionary word does not carry.
        if language == .hebrew, isMaterLectionis(extra) { return 55 }
        // A double tap — the same key landing twice.
        if extra == leftNeighbor || extra == rightNeighbor { return 55 }
        // A stray key beside the one that was meant, still cheaper than a
        // wild guess but not as cheap as a clean double-tap or a Hebrew
        // spelling convention, because "adjacent to the letter before or
        // after it" is a weaker signal than "identical to it."
        if let leftNeighbor, KeyProximity.areAdjacent(extra, leftNeighbor, in: language) { return 70 }
        if let rightNeighbor, KeyProximity.areAdjacent(extra, rightNeighbor, in: language) { return 70 }
        return plainEdit
    }

    // MARK: Transposition

    /// Two adjacent letters swapped — `teh` for `the`, `תדוה` for `תודה` — is
    /// the commonest slip there is, which is the whole reason Damerau's
    /// extension to Levenshtein exists rather than paying for it as two
    /// substitutions.
    private static let transpositionCost = 60

    // MARK: Folding

    /// `SeedLanguageModel.fold`, one character at a time.
    ///
    /// **Deliberately not shape-folding Hebrew final forms.** `fold` already
    /// leaves `ם`/`מ` and the other four pairs distinct — it only lowercases,
    /// normalises to NFC, and folds the maqaf and curly apostrophe onto their
    /// ASCII spellings — which is exactly right here: `substitutionCost`
    /// charges 20 for a final-form pair, and folding the difference away
    /// before it gets there would make the two letters indistinguishable and
    /// that whole rule dead code.
    private static func fold(_ character: Character) -> Character {
        SeedLanguageModel.fold(String(character)).first ?? character
    }
}
