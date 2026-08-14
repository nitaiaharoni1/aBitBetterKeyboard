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
    }

    /// Where a candidate came from, ordered worst to best so the raw value can
    /// carry the weight.
    ///
    /// The gaps between tiers are large on purpose: a source is a statement about
    /// *how sure* we are, and no amount of frequency inside a weaker source should
    /// climb over a stronger one. A word the user typed into Settings by hand
    /// outranks anything Apple's dictionary has to say about it, always.
    enum Source: Int, Comparable {
        /// `UITextChecker.guesses` — a correction, i.e. a claim the user mis-typed.
        case correction = 0
        /// `UITextChecker.completions` — a longer word starting with what was typed.
        case checker = 1
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
        case codeSwitch = 5
        /// A common word one keystroke away from what was typed.
        ///
        /// **Below a completion, because it disagrees with a key that was
        /// pressed.** `מונ` on the way to `מונית` is one edit from `מוכן`, and
        /// ranking the neighbour higher pushed the word the user was actually
        /// typing out of the bar. A completion is consistent with every keystroke
        /// so far; a neighbour asserts that one of them was a mistake, which is a
        /// larger claim and needs to lose the tie.
        case neighbour = 2
        /// The bundled seed list.
        case seed = 3
        /// A word already committed in this field.
        ///
        /// **Above the seed list, because the field is a better prior than the
        /// average message.** Completing `ele` to `electricity` while the sentence
        /// already contains `elephant` is the seed list ignoring the only evidence
        /// sitting in front of it. Below code-switch and learned: a word this
        /// person always types, or a Latin work-word inside a Hebrew sentence, is
        /// still a stronger claim than "it appeared once above".
        case document = 4
        /// A word this user types often.
        case learned = 6
        /// Deterministic orthography: a dropped apostrophe, a Hebrew final form.
        case orthography = 7
        /// The user's own dictionary, or `UILexicon`.
        case personal = 8
        /// The same keys on the other layout, landing on a common word.
        case layout = 9
        /// Exactly what was keyed. Never ranked — it is pinned to slot zero.
        case typed = 10

        static func < (lhs: Source, rhs: Source) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// How good a candidate is, high wins.
    ///
    /// Three terms, and they are deliberately readable rather than tuned:
    ///
    /// - **the source**, worth 1000 each, so tiers never interleave;
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
        var total = Double(candidate.source.rawValue) * 1000
        if candidate.followsContext { total += 400 }
        if let rank = SeedLanguageModel.rank(of: candidate.text, in: candidate.language) {
            // Rank 0 is worth the full 300 and it decays; the exact curve does not
            // matter, only that common beats rare inside a tier.
            total += 300 / (1 + Double(rank) / 60)
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
    static func rank(_ candidates: [Candidate], limit: Int) -> [Suggestion] {
        var seen = Set<String>()
        var out: [Suggestion] = []

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
            out.append(Suggestion(text: candidate.text, language: candidate.language))
            if out.count == limit { break }
        }
        return out
    }
}
