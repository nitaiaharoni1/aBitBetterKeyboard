extension KeyboardController {

    // MARK: Suggestions

    public func refreshSuggestions() {
        guard store.storedPredictions else {
            suggestions = []
            return
        }
        let prefix = currentWordPrefix
        let before = contextBefore
        let context = prefix.isEmpty ? before : String(before.dropLast(prefix.count))
        let results = SuggestionEngine.suggestions(
            prefix: prefix,
            context: context,
            languages: [language] + store.enabledLanguages.filter { $0 != language },
            supplementary: store.storedPersonalDictionary + supplementaryWords,
            personal: personal
        )
        // When autocorrect is off, space must leave the typed word alone — so the
        // bold "default" slot has to be that word, not a correction the space bar
        // is no longer allowed to commit. Next-word suggestions (empty prefix) are
        // never auto-committed anyway; leave their middle bold alone.
        if !store.storedAutocorrect, !prefix.isEmpty {
            suggestions = SuggestionEngine.markDefault(results, at: 0)
        } else {
            suggestions = results
        }
        askForRefinement(prefix: prefix, context: context)
    }

    /// Start the async tier's clock. Every keystroke restarts it, so it only ever
    /// fires into a pause.
    private func askForRefinement(prefix: String, context: String) {
        guard let refiner else { return }
        refiner.refine(
            PredictiveRefiner.Request(
                textBefore: context,
                wordInProgress: prefix,
                language: language,
                // Only a live session. The scripted demo `MockScreenContext` plays
                // when nothing is broadcasting is the right thing to show on a
                // marketing screen and the wrong thing to predict a real reply
                // from.
                screenContext: ScreenContextSession.shared.isLive
                    ? ScreenContextSession.shared.state.context : nil,
                permitted: SecureField.permitsRead(
                    secure: target?.isSecureTextEntry ?? nil, contentType: fieldContentType),
                localSlotCount: suggestions.count))
    }

    /// Put the model's words into slots 1 and 2.
    ///
    /// **Three things this must never do, and they are the contract the async tier
    /// is allowed to exist under.**
    ///
    /// It never touches slot 0, because that is the literal keystrokes and the
    /// user must always be able to commit exactly what they typed.
    ///
    /// It never moves the bold slot. `markDefault` is re-applied at whatever index
    /// the local tier chose, so what the space bar commits is decided by
    /// deterministic local code and cannot change while somebody is looking at the
    /// bar deciding whether to press space.
    ///
    /// And it never applies to a document that has moved on. The answer took
    /// hundreds of milliseconds to arrive; if the word in progress changed while
    /// it was in flight it is an answer to a question nobody is asking any more.
    func applyRefinement(_ words: [String], for prefix: String) {
        guard store.storedPredictions, prefix == currentWordPrefix,
            let first = suggestions.first
        else { return }
        let defaultIndex = suggestions.firstIndex(where: \.isDefault) ?? 0
        var merged = [first]
        for word in words where SeedLanguageModel.fold(word) != SeedLanguageModel.fold(first.text) {
            merged.append(Suggestion(text: word, language: language))
            if merged.count == 3 { break }
        }
        // Backfilled from what the local tier had, so a model that returned one
        // usable word costs the user a slot rather than leaving a gap.
        for candidate in suggestions.dropFirst() where merged.count < suggestions.count {
            if !merged.contains(where: {
                SeedLanguageModel.fold($0.text) == SeedLanguageModel.fold(candidate.text)
            }) {
                merged.append(candidate)
            }
        }
        suggestions = SuggestionEngine.markDefault(merged, at: defaultIndex)
    }

    /// Drop anything the async tier is waiting on. Called as the keyboard goes
    /// away; an answer that arrives afterwards would land in the next document.
    public func cancelRefinement() {
        refiner?.cancel()
    }

    public func updateSupplementaryLexicon(_ words: [String]) {
        supplementaryWords = words
        refreshSuggestions()
    }

    public func apply(_ suggestion: Suggestion) {
        Feedback.keyPress()
        // Text in, so it sounds like text going in. Tapping a candidate is the
        // one insertion that reaches the document without a `KeyCap` behind it,
        // and `press(_:)` is where every other one gets its click.
        Feedback.keyClick(.tock)
        replaceCurrentWord(with: suggestion.text)
        learnWordJustCommitted()
        target?.insertText(" ")
        refreshSuggestions()
    }

    /// Remember the word the user has just finished, and the pair it makes with
    /// the one before it.
    ///
    /// **Called after the word is settled, never at the keystroke.** A word being
    /// typed is not a word yet — learning `addres` on the way to `address` would
    /// teach the store every prefix of everything, and prefixes are exactly what
    /// the store is later asked about. Both callers are moments the user has
    /// finished a word on purpose: pressing space, or tapping a candidate.
    ///
    /// Three things can stop it, and each is somebody's explicit decision rather
    /// than a heuristic: the setting is off, the field is a credential field, or
    /// the App Group is out of reach because Full Access was never granted — in
    /// which case `PersonalLanguageModel` has nowhere to persist and quietly keeps
    /// its counts for as long as this keyboard instance lives.
    func learnWordJustCommitted() {
        let words = SuggestionEngine.previousWords(in: contextBefore)
        guard let word = words.last else { return }
        personal.record(
            word: word,
            previous: words.count >= 2 ? words[words.count - 2] : nil,
            // The word's own script, not the layout's. Somebody typing a Hebrew
            // sentence has the Hebrew layout up, and the English words inside it
            // belong in the English counters or `לעבודה` and `sprint` end up in one
            // list where neither can be looked up.
            language: SuggestionEngine.dominantLanguage(
                in: word, among: [language] + store.enabledLanguages.filter { $0 != language })
                ?? language,
            // The same question `SecureField` answers for a screen read, asked
            // again here because "may I keep this word" and "may I send this
            // screen" have the same answer for a password.
            permitted: store.storedLearnsFromTyping
                && SecureField.permitsRead(
                    secure: target?.isSecureTextEntry ?? nil, contentType: fieldContentType)
        )
    }
}
