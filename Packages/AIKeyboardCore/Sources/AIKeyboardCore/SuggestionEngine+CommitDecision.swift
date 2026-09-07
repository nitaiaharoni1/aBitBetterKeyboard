import Foundation

extension SuggestionEngine {
    /// Why pressing space may replace what was typed, or nil to keep the
    /// keystrokes. The cascade works from proof that a replacement is safe to
    /// progressively weaker evidence, so a refusal at a decision gate is final.
    @MainActor
    static func commitReason(
        _ prefix: String, previousWords: [String], context: String = "",
        typedLanguage: KeyboardLanguage,
        results: [Candidate], supplementary: [String], personal: PersonalLanguageModel,
        alternatives: [Candidate]? = nil
    ) -> CommitReason? {
        guard results.count > 1 else { return nil }
        let word = wordCore(prefix)
        let lower = word.lowercased()
        let typed = comparable(prefix)
        guard
            !protectsTypedWord(
                word: word, typed: typed, supplementary: supplementary,
                personal: personal, language: typedLanguage)
        else { return nil }
        var evaluation = CommitEvaluation(
            word: word, lower: lower, typed: typed, previousWords: previousWords, context: context,
            typedLanguage: typedLanguage, results: results, supplementary: supplementary,
            personal: personal, alternatives: alternatives)
        if evaluation.rejectsWinner || evaluation.refusesContestedEntry { return nil }
        if let result = terminalReason(for: evaluation.layoutDecision()) { return result }
        if let result = terminalReason(for: evaluation.orthographyDecision()) { return result }
        guard !SeedLanguageModel.knows(evaluation.word, in: typedLanguage),
            let first = evaluation.offers.first,
            isAutomaticallyInsertable(first.text),
            commitTrustsReading(first, typed: evaluation.word)
        else { return nil }
        if correctionIsAmbiguous(
            typed: evaluation.word, winner: first, alternatives: alternatives ?? results)
        {
            return nil
        }
        if let reason = evaluation.sentenceFollowerReason(for: first) { return reason }
        guard let locale = typedLanguage.spellCheckerLocale else { return nil }
        let facts = evaluation.facts(for: first, checkerLocale: locale)
        return evaluation.remainingDecision(for: facts)
    }

    @MainActor
    private static func protectsTypedWord(
        word: String, typed: String, supplementary: [String],
        personal: PersonalLanguageModel, language: KeyboardLanguage
    ) -> Bool {
        if !typed.isEmpty, supplementary.contains(where: { comparable($0) == typed }) { return true }
        return personal.isProtected(word, in: language)
    }

    private enum CommitDecision {
        case continueEvaluation
        case refuse
        case reason(CommitReason)
    }

    /// A missing outer optional means the cascade should continue. A present
    /// nil means a gate has made a final refusal.
    private static func terminalReason(for decision: CommitDecision) -> CommitReason?? {
        switch decision {
        case .continueEvaluation: return nil
        case .refuse: return .some(nil)
        case let .reason(reason): return .some(reason)
        }
    }

    /// The derived values and two lazy memoized questions shared by the ordered
    /// gates. Keeping the values here preserves the original cascade's answer
    /// while making a final refusal distinct from a gate that should continue.
    @MainActor
    private struct CommitEvaluation {
        let word: String
        let lower: String
        let typed: String
        let previousWords: [String]
        let context: String
        let typedLanguage: KeyboardLanguage
        let offers: ArraySlice<Candidate>
        let competingOffers: [Candidate]
        let supplementary: [String]
        let personal: PersonalLanguageModel
        var hebrewContinuation: Bool?
        var expected: Set<String>?

        init(
            word: String, lower: String, typed: String, previousWords: [String], context: String,
            typedLanguage: KeyboardLanguage, results: [Candidate], supplementary: [String],
            personal: PersonalLanguageModel, alternatives: [Candidate]?
        ) {
            self.word = word
            self.lower = lower
            self.typed = typed
            self.previousWords = previousWords
            self.context = context
            self.typedLanguage = typedLanguage
            offers = results.dropFirst()
            competingOffers = Array(offers) + (alternatives ?? []).filter { $0.source != .typed }
            self.supplementary = supplementary
            self.personal = personal
        }

        var rejectsWinner: Bool {
            guard let first = offers.first else { return false }
            return personal.isRejectedCorrection(
                original: word, replacement: wordCore(first.text), language: first.language)
        }

        /// A supplementary completion may finish an otherwise uncontested word,
        /// but must not outrank a different candidate that continues the same keys.
        var refusesContestedEntry: Bool {
            guard !typed.isEmpty, let first = offers.first else { return false }
            let entry = comparable(first.text)
            let contested = competingOffers.contains {
                let other = comparable($0.text)
                return other != entry && other != typed && other.hasPrefix(typed)
            }
            return entry != typed && entry.hasPrefix(typed) && contested
                && supplementary.contains(where: { comparable($0) == entry })
        }

        /// Wrong-layout text is not spelling. When the surrounding script says
        /// a switch is deliberate and another offer continues the keys, refuse
        /// rather than let the later spelling gates commit the transposition.
        func layoutDecision() -> CommitDecision {
            guard let first = offers.first, first.language.script != typedLanguage.script
            else { return .continueEvaluation }
            let switching =
                SuggestionEngine.dominantLanguage(in: context).map {
                    $0.script != typedLanguage.script
                } ?? false
            let stillSpellingSomething = competingOffers.contains {
                let other = comparable($0.text)
                return $0.language.script == typedLanguage.script && other != typed
                    && other.hasPrefix(typed)
            }
            return switching && stillSpellingSomething ? .refuse : .reason(.wrongLayout)
        }

        /// Orthography may commit only the candidate this rule generated. Hebrew
        /// final forms also require that the typed letters have no continuation.
        func orthographyDecision() -> CommitDecision {
            if typedLanguage == .english, let contraction = contractions[lower] {
                guard !ambiguousContractions.contains(lower) else { return .refuse }
                return orthographyWins(contraction) ? .reason(.contraction) : .refuse
            }
            if typedLanguage.script == .hebrew, let final = hebrewFinalFormCorrection(of: word),
                SeedLanguageModel.words(startingWith: word, in: typedLanguage, limit: 1).isEmpty
            {
                return orthographyWins(final) ? .reason(.hebrewFinalForm) : .refuse
            }
            return .continueEvaluation
        }

        /// Sentence context can replace a non-continuing Hebrew word, the one
        /// place it outranks a dictionary verdict. It cannot finish a prefix.
        func sentenceFollowerReason(for first: Candidate) -> CommitReason? {
            let winner = SeedLanguageModel.fold(first.text)
            let typedFolded = SeedLanguageModel.fold(word)
            guard typedLanguage.script == .hebrew,
                !winner.hasPrefix(typedFolded),
                SeedLanguageModel.followers(after: previousWords, in: typedLanguage)
                    .contains(where: { SeedLanguageModel.fold($0) == winner })
            else { return nil }
            return .sentenceFollower
        }

        /// The checker verdict, neighbour lookup, and prefix facts retain their
        /// original order. The lazy continuation and follower scans still happen
        /// only in the gates that read them.
        func facts(for first: Candidate, checkerLocale: String) -> CommitFacts {
            let known = isKnownWord(word, checkerLocale: checkerLocale)
            let winner = SeedLanguageModel.fold(first.text)
            let typedFolded = SeedLanguageModel.fold(word)
            let neighbourMatch =
                !known
                && neighbourWords(of: word, in: typedLanguage, personal: personal, limit: 3)
                    .contains(where: { SeedLanguageModel.fold($0) == winner })
            let transposed = SeedLanguageModel.isTransposition(winner, of: word)
            let sameLengthSlip = typedFolded.count == winner.count && !transposed
            let continuations = SeedLanguageModel.words(
                startingWith: word, in: typedLanguage, limit: completionPoolLimit)
            return CommitFacts(
                first: first, known: known, winner: winner, typedFolded: typedFolded,
                neighbourMatch: neighbourMatch, transposed: transposed,
                sameLengthSlip: sameLengthSlip, ambiguousStem: hasDistinctLexemes(continuations),
                prefixCompletion: typedFolded.count < winner.count && winner.hasPrefix(typedFolded))
        }

        mutating func remainingDecision(for facts: CommitFacts) -> CommitReason? {
            if let decision = neighbourDecision(for: facts) { return decision }
            if let decision = frequencyDecision(for: facts) { return decision }
            if refusesAmbiguousCompletion(for: facts) { return nil }
            return fallbackDecision(for: facts)
        }

        private func orthographyWins(_ correction: String) -> Bool {
            guard let winner = offers.first, winner.source == .orthography else { return false }
            return comparable(winner.text) == comparable(correction)
        }

        /// A same-length Hebrew substitution can be an unfinished word, while a
        /// transposition remains an explainable slip and keeps its stronger reason.
        private mutating func neighbourDecision(for facts: CommitFacts) -> CommitReason? {
            guard facts.neighbourMatch,
                !hebrewWordInProgress(sameLengthSlip: facts.sameLengthSlip),
                !(facts.prefixCompletion && facts.ambiguousStem)
            else { return nil }
            return facts.transposed ? .transposition : .singleEdit
        }

        /// Frequency correction requires a common winner, an unknown typed word,
        /// a non-prefix replacement, and a priced path through the typo channel.
        private mutating func frequencyDecision(for facts: CommitFacts) -> CommitReason? {
            guard !facts.winner.hasPrefix(facts.typedFolded),
                TypoLexicon.rank(of: facts.first.text, in: typedLanguage) != nil,
                !TypoLexicon.isWord(word, in: typedLanguage),
                let budget = TypoChannel.budget(forTypedLength: word.count),
                let priced = TypoChannel.cost(
                    typed: Array(word), candidate: Array(facts.first.text), language: typedLanguage,
                    budget: budget),
                !hebrewWordInProgress(sameLengthSlip: facts.sameLengthSlip)
            else { return nil }
            return .frequency(cost: priced.cost, transposition: facts.transposed, count: priced.count)
        }

        /// An unfinished stem with distinct readings may continue only when the
        /// sentence expects this winner. The cached follower set keeps the three
        /// original ambiguity gates from re-walking the field.
        private mutating func refusesAmbiguousCompletion(for facts: CommitFacts) -> Bool {
            if facts.ambiguousStem, !sentenceExpects(facts.winner) { return true }
            if facts.prefixCompletion, typedLanguage.script == .hebrew, facts.first.source == .checker {
                let readings = continuingOffers(from: facts)
                if hasDistinctHebrewLexemes(readings), !sentenceExpects(facts.winner) { return true }
            }
            if facts.prefixCompletion, typedLanguage.script == .latin,
                SuggestionEngine.dominantLanguage(in: context)?.script == .hebrew
            {
                let offered = continuingOffers(from: facts)
                if hasDistinctLexemes(offered), !sentenceExpects(facts.winner) { return true }
            }
            return false
        }

        /// The final four-letter fallback is deliberately weaker evidence. It
        /// preserves the Hebrew same-length-substitution refusal from the neighbour gate.
        private func fallbackDecision(for facts: CommitFacts) -> CommitReason? {
            guard word.count >= 4, !facts.known,
                !(facts.neighbourMatch && facts.sameLengthSlip && typedLanguage.script == .hebrew)
            else { return nil }
            let explainable =
                TypoChannel.budget(forTypedLength: word.count).map { budget in
                    TypoChannel.cost(
                        typed: Array(word), candidate: Array(facts.first.text),
                        language: typedLanguage, budget: budget) != nil
                } ?? false
            return .unknownWord(explainable: explainable)
        }

        /// This expensive lexicon scan is lazy: only Hebrew same-length slips can
        /// read it, and both neighbour and frequency gates share its answer.
        private mutating func hebrewWordInProgress(sameLengthSlip: Bool) -> Bool {
            guard typedLanguage.script == .hebrew, sameLengthSlip else { return false }
            if let hebrewContinuation { return hebrewContinuation }
            let answer = TypoLexicon.hasContinuation(of: word, in: typedLanguage)
            hebrewContinuation = answer
            return answer
        }

        private mutating func sentenceExpects(_ candidate: String) -> Bool {
            if let expected { return expected.contains(candidate) }
            let followers = Set(
                contextFollowers(
                    last: previousWords, field: documentWords(in: context),
                    language: typedLanguage, personal: personal
                ).map(SeedLanguageModel.fold))
            expected = followers
            return followers.contains(candidate)
        }

        private func continuingOffers(from facts: CommitFacts) -> [String] {
            competingOffers.map(\.text).filter {
                let other = SeedLanguageModel.fold($0)
                return other != facts.typedFolded && other.hasPrefix(facts.typedFolded)
            }
        }
    }

    private struct CommitFacts {
        let first: Candidate
        let known: Bool
        let winner: String
        let typedFolded: String
        let neighbourMatch: Bool
        let transposed: Bool
        let sameLengthSlip: Bool
        let ambiguousStem: Bool
        let prefixCompletion: Bool
    }
}
