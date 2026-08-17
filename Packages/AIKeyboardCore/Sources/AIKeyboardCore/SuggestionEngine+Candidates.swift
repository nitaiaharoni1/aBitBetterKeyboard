import Foundation

extension SuggestionEngine {

    /// One thing the bar could offer, and where it came from.
    ///
    /// **Provenance is kept because the ranking is made of it.** The old engine
    /// appended candidates in a fixed order and took the first three, which meant
    /// the order in which the code happened to be written *was* the ranking — and
    /// that is how `helot` ended up ahead of `hello` and `הכתום` ahead of
    /// `הכתובת`. Attaching the source to the candidate lets a later stage weigh a
    /// word the user has typed forty times against one Apple's dictionary offered,
    /// which is a judgement no append order can express.
    struct Candidate {
        let text: String
        let language: KeyboardLanguage
        let source: Source
        /// How many Hebrew clitic letters had to be stripped to reach the stem this
        /// was completed from. Zero for everything else. See `score`.
        var cliticDepth: Int = 0
        /// Set when the previous word in the sentence is known to be followed by
        /// this one.
        var followsContext: Bool = false
        /// Where this sat in the list its source returned it in.
        ///
        /// **A source's own order is information and throwing it away cost three
        /// corpus entries.** The first ranking scored every `UITextChecker`
        /// completion identically when the seed list had nothing to say about any
        /// of them, so the tie fell to the alphabetical tie-break and `depl`
        /// offered `depletion` and `deplorable` while `deploy` — which the checker
        /// had put in the list itself — dropped off the end. The checker has no
        /// frequency model, but its order is not nothing, and where this engine
        /// knows nothing it should keep what it was given.
        var ordinal: Int = 0
        /// The typed word and this neighbour differ by one key that sits next
        /// to the one that was pressed. Ranking only; `shouldAutocorrect`
        /// still refuses a same-length substitution that is not a transposition.
        var keyAdjacent: Bool = false
        /// How often this person has committed this word. Stamped before
        /// `rank` so `score` stays a pure function of the candidate.
        var personalCount: Int = 0
    }

    /// Where a candidate came from, ordered worst to best so the raw value can
    /// carry the weight.
    ///
    /// The gaps between tiers are large on purpose: a source is a statement about
    /// *how sure* we are, and no amount of frequency inside a weaker source should
    /// climb over a stronger one. A word the user typed into Settings by hand
    /// outranks anything Apple's dictionary has to say about it, always.
    ///
    /// **Numbered in tens, and `score` multiplies by 100, so a tier is still worth
    /// the same 1000 it always was.** Every value here was one apart and the scale
    /// had no way to say "between these two" — which is a thing this ranking needs
    /// to say: `hebrewIrregularPlurals` is a looked-up word and belongs above the
    /// unranked completion list and the neighbour guess, and below the frequency
    /// prior. The alternative was reusing `.seed` for it, which throws away the
    /// provenance this type exists to carry. No score moved when the values were
    /// widened; `irregular` is the only new one.
    enum Source: Int, Comparable {
        /// Another ending on a Hebrew word that is already finished — `רוצה` →
        /// `רוצים`. See `SuggestionEngine.hebrewInflections`.
        ///
        /// **Below everything, on purpose, and the negative tier is the point.**
        /// Hebrew replaces its endings rather than appending them, so a prefix
        /// search cannot reach these and something has to build them; a rule that
        /// *builds* words has no business outranking one that looked a word up.
        /// Ranked here it can only ever fill a slot no other source wanted, which
        /// is exactly the measured need — 7 of 20 common finished Hebrew words
        /// drew a bar with empty slots because `UITextChecker` had nothing — and
        /// it makes the change safe to measure, since no moment where the bar was
        /// already full can move.
        case inflection = -10
        /// `UITextChecker.guesses` — a correction, i.e. a claim the user mis-typed.
        case correction = 0
        /// The same claim, made by a frequency-ranked list instead of by Apple.
        /// See `SuggestionEngine.frequencyCorrections` and `TypoLexicon`.
        ///
        /// **Above `.correction` and below `.checker`, and both halves of that
        /// were forced by the report this source exists for.** Somebody typed
        /// `דוגמטןת` for `דוגמאות` ("examples") — two adjacent-key slips, `א` for
        /// `ט` and `ו` for `ן`, which sit side by side on the Hebrew top row. No
        /// source in this engine generates a candidate two edits out, so the bar
        /// held exactly one offer: `דוגמטית`, which Apple's `guesses` reached in
        /// one edit and which appears nowhere in 50,000 words of real Hebrew,
        /// while `דוגמאות` is rank 3,643. So it has to beat `.correction`: an
        /// unranked guess is the weakest evidence in the bar and this is the same
        /// claim with a frequency prior behind it.
        ///
        /// It must lose to `.checker` for the opposite reason. This is a
        /// *correction*, so it disagrees with a key the user pressed, and a
        /// completion agrees with all of them — the rule `.neighbour` is already
        /// written under. Below the lowest completion tier there is, it can only
        /// ever win a slot on a word nothing is still completing, which is what
        /// keeps it away from a word that is merely half typed.
        case frequency = 5
        /// `UITextChecker.completions` — a longer word starting with what was typed.
        case checker = 10
        /// A word list this repo wrote for Latin words inside Hebrew sentences.
        ///
        /// **Above both the checker and the seed list, and that is the entire
        /// reason it exists.** Below the checker, `spri` inside a Hebrew sentence
        /// offers `spring` and `sprinkle` and never reaches `sprint`. Below the
        /// seed, `sta` offers `station` and `start` and never reaches `standup` —
        /// which is the same failure one tier further up, found by
        /// `SuggestionEngineTests` after the first reordering. Only ever populated
        /// when the sentence around the word is Hebrew, so it cannot outrank
        /// Apple's ranking inside an English one.
        case codeSwitch = 50
        /// A common word one keystroke away from what was typed.
        ///
        /// **Below a completion, because it disagrees with a key that was
        /// pressed.** `מונ` on the way to `מונית` is one edit from `מוכן`, and
        /// ranking the neighbour higher pushed the word the user was actually
        /// typing out of the bar. A completion is consistent with every keystroke
        /// so far; a neighbour asserts that one of them was a mistake, which is a
        /// larger claim and needs to lose the tie.
        case neighbour = 20
        /// A Hebrew plural no ending can build, read out of
        /// `SuggestionEngine.hebrewIrregularPlurals`.
        ///
        /// **Above the completion list and the neighbour, below the frequency
        /// prior, and every one of those three placements was measured.** At
        /// `.inflection` — where the rule that *builds* endings correctly sits — it
        /// filled only the slots nothing else wanted, which turned out to be 5 of
        /// the 21 words in the table: `בית` drew `בית-המשפט`, `ביתי`, `בית-הספר`,
        /// `בן` drew three surnames, and `שנה` drew `שנהב` ("ivory") while `שנים`
        /// — rank 53 in 50,000 words of real Hebrew — was nowhere. Those all come
        /// from `UITextChecker`, which has no frequency model, so a hand-checked
        /// table of the commonest words in the language is the better evidence and
        /// has to outrank it.
        ///
        /// **It is not `.seed`, and the gap below that tier is deliberate.** The
        /// seed list carries a frequency order this table does not, so a seed word
        /// arrives with up to 300 of rank behind it and wins; and a seed reading at
        /// one clitic lands on exactly 2500, which is why this is 26 and not 25.
        ///
        /// Nothing here can be committed by the space bar. Every word in the table
        /// is a word, and `shouldAutocorrect` refuses at `SeedLanguageModel.knows`
        /// or at `!known` in the four-letter gate for all of them — measured as
        /// zero commits moved across the sweep.
        case irregular = 26
        /// The bundled seed list.
        case seed = 30
        /// A word already committed in this field.
        ///
        /// **Above the seed list, because the field is a better prior than the
        /// average message.** Completing `ele` to `electricity` while the sentence
        /// already contains `elephant` is the seed list ignoring the only evidence
        /// sitting in front of it. Below code-switch and learned: a word this
        /// person always types, or a Latin work-word inside a Hebrew sentence, is
        /// still a stronger claim than "it appeared once above".
        case document = 40
        /// A word this user types often.
        case learned = 60
        /// Deterministic orthography: a dropped apostrophe, a Hebrew final form.
        case orthography = 70
        /// The user's own dictionary, or `UILexicon`.
        case personal = 80
        /// The same keys on the other layout, landing on a common word.
        case layout = 90
        /// Exactly what was keyed. Never ranked — it is pinned to slot zero.
        case typed = 100

        static func < (lhs: Source, rhs: Source) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// How good a candidate is, high wins.
    ///
    /// Three terms, and they are deliberately readable rather than tuned:
    ///
    /// - **the source**, worth 1000 a tier, so tiers never interleave. `Source` is
    ///   numbered in tens against a multiplier of 100, which is what leaves room
    ///   for a half-step like `.irregular`;
    /// - **the sentence**, worth 400 — enough to move a candidate a full tier,
    ///   because "the word before it was `בעוד`" is stronger evidence than which
    ///   dictionary a word came out of. This is the term that puts `תור` after
    ///   `לקבוע` ahead of the commoner `תודה`, and `much` after `so`;
    /// - **the frequency**, worth up to 300, from the seed list's rank. Absent
    ///   from the seed means zero here, never a penalty: most words are absent,
    ///   and the list is a prior over the common core rather than a dictionary.
    ///
    /// **Clitic depth costs half a tier per letter, which is much more than a
    /// tie-break and is meant to be.** Every letter stripped off the front of a
    /// Hebrew word is an assumption about how the word is built, and two of them
    /// is a guess stacked on a guess: `שלמו` read as `ש` + `ל` + `מוכן` produces
    /// `שלמוכן`, a real construction that nobody has ever typed, and at a small
    /// penalty it outranked `שלום` — the word the user obviously meant. Half a
    /// tier per letter puts a two-clitic reading below a plain neighbour and a
    /// one-clitic reading below a plain completion, which is the right order of
    /// confidence, while still leaving `לעבו` → `לעבודה` far ahead of anything
    /// Apple's dictionary offers for the glued form.
    static func score(_ candidate: Candidate) -> Double {
        var total = Double(candidate.source.rawValue) * 100
        if candidate.followsContext { total += 400 }
        if let rank = SeedLanguageModel.rank(of: candidate.text, in: candidate.language) {
            // Rank 0 is worth the full 300 and it decays; the exact curve does not
            // matter, only that common beats rare inside a tier.
            total += 300 / (1 + Double(rank) / 60)
        }
        // The same 300 budget as the seed prior, for a word this person has
        // actually used. Two sightings is the floor (`boostThreshold`): one
        // may be a typo. Habits can outrank a commoner word they never type
        // and cannot climb a source tier.
        if candidate.personalCount >= PersonalLanguageModel.boostThreshold {
            total += 300 / (1 + 4 / Double(candidate.personalCount))
        }
        // Small enough that one word being in the seed list still beats another
        // being earlier in its source's list, and large enough to survive the
        // alphabetical tie-break when neither is.
        total -= Double(candidate.ordinal) * 8
        total -= Double(candidate.cliticDepth) * 500
        // Below frequency and context, above the source-list ordinal. A
        // fat-finger re-ranks two neighbours; it does not commit one.
        if candidate.keyAdjacent { total += 50 }
        return total
    }

    /// The three slots, literal first, best of the rest after it.
    ///
    /// Slot zero is pinned rather than scored. The rule that the user can always
    /// commit exactly what they keyed is older than this ranking and does not
    /// depend on it: whatever the model believes, a person who typed `qwt` must be
    /// able to keep `qwt`.
    ///
    /// **Hands back candidates rather than suggestions, because the commit
    /// decision needs the provenance this stage spent its whole life weighing.**
    /// It used to flatten to `[Suggestion]` here, which keeps the words and throws
    /// away where each came from — so `shouldAutocorrect`, one call further on,
    /// could not tell a seed completion of a plain Hebrew stem from the same
    /// dictionary read through two clitics, and committed `להתרופה` for `להתר`.
    /// See `commitTrustsReading`. The bar still draws `Suggestion`s; the two
    /// callers build them at the point they are drawn.
    static func rank(_ candidates: [Candidate], limit: Int) -> [Candidate] {
        var seen = Set<String>()
        var out: [Candidate] = []

        let typed = candidates.filter { $0.source == .typed }
        let rest = candidates.filter { $0.source != .typed }
            // `sorted(by:)` is not stable, so the tie-break has to be total or two
            // runs over one input can disagree about which word is slot 1.
            .sorted {
                let (left, right) = (score($0), score($1))
                return left == right ? $0.text < $1.text : left > right
            }

        for candidate in typed + rest {
            let key = SeedLanguageModel.fold(candidate.text)
            guard !key.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            out.append(candidate)
            if out.count == limit { break }
        }
        return out
    }
}
