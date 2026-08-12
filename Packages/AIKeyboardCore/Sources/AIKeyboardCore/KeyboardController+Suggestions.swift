extension KeyboardController {

    // MARK: Suggestions

    public func refreshSuggestions() {
        // **Above the Predictions guard, because it is not about predictions.**
        // Fix and Rewrite are drawn disabled on an empty field, and this is what
        // their keys redraw from; leaving it under the guard would freeze both keys
        // in whatever state they were in for anyone who has turned the suggestion
        // bar off. This function is the one thing every document change already
        // goes through, including the host's own `textDidChange`.
        refreshDocumentState()
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

    /// Re-reads the two facts about the document that the keys are drawn from,
    /// without touching the suggestion bar or the async tier.
    ///
    /// **Separate from `refreshSuggestions` because the extension needs one of
    /// them without the other.** `KeyboardViewController.viewWillAppear` has to
    /// know whether the field it is coming up over has anything in it, or Fix and
    /// Rewrite are drawn from whatever the last field left behind — and calling
    /// the full refresh there would start `PredictiveRefiner`'s clock, which means
    /// a model call every time the keyboard appears, for a word nobody has begun
    /// typing.
    ///
    /// The second fact is that an edit can only be taken back while the text it
    /// replaced is still standing. **A host that empties the field — the message
    /// was sent — is the case that matters**, because nothing the user did clears
    /// the revert there: the send happened in the other app, `textDidChange`
    /// brings the news, and without this the revert button would still be sitting
    /// in the bar offering to type a sent message back into an empty box. Ordered
    /// after the flag so it reads the fresh answer, and safe to run from inside
    /// `replaceTargetText` — `applyDirectly` records the edit *after* that call
    /// returns, so this can never delete the edit that is being made.
    public func refreshDocumentState() {
        documentHasText = hasTextToWorkWith
        if revertibleEdit != nil, !documentHasText { revertibleEdit = nil }
    }

    /// Start the async tier's clock. Every keystroke restarts it, so it only ever
    /// fires into a pause.
    private func askForRefinement(prefix: String, context: String) {
        guard let refiner else { return }
        // **Not while somebody is speaking.** A recording rewrites the tail of the
        // field every couple of seconds as a better reading of the same words
        // arrives (see `KeyboardController.replaceStreamedDictation`), and every
        // one of those rewrites reaches the host's `textDidChange` and lands here —
        // so a thirty-second dictation would buy a dozen model calls to predict the
        // next word of a sentence the user is not typing. The local tier still
        // runs; it is free.
        guard !isDictating else { return }
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

    /// Put the model's words into the slots the local tier is not holding.
    ///
    /// **Three things this must never do, and they are the contract the async tier
    /// is allowed to exist under.**
    ///
    /// It never touches slot 0, because that is the literal keystrokes and the
    /// user must always be able to commit exactly what they typed.
    ///
    /// It never changes what the space bar would insert. **Pinning the bold
    /// *index* is not enough and this used to do only that**: `markDefault` was
    /// re-applied at the local tier's index over a list whose contents the model
    /// had already replaced, so the word under the bold slot became the model's
    /// while the index stood still. That is the exact harm the two-tier split
    /// exists to prevent — the user reads the bar, pauses to think, presses space,
    /// and gets a word they never saw. It is reachable wherever the local tier
    /// autocorrects with a thin bar: four of the ninety corpus entries sit at
    /// default index 1 with two slots (`tomorow` → `tomorrow`), which is exactly
    /// the state `PredictiveRefiner.shouldRefine` lets through mid-word, and
    /// `refine` serves a cached answer synchronously, so not even the 300 ms
    /// cushion stands between the keystroke and the swap.
    ///
    /// **The pin is scoped to a word in progress, because that is when space
    /// commits at all.** `insertSpace` leaves an empty prefix alone, so with
    /// nothing typed the bold slot is a tap target rather than something the space
    /// bar will insert — and refining the likeliest next word is the whole point
    /// of the tier. So: prefix empty, everything below slot 0 is the model's to
    /// replace; mid-word, the default slot's contents are the local tier's and
    /// stay.
    ///
    /// And it never applies to a document that has moved on. The answer took
    /// hundreds of milliseconds to arrive; if the word in progress changed while
    /// it was in flight it is an answer to a question nobody is asking any more.
    func applyRefinement(_ words: [String], for prefix: String) {
        guard store.storedPredictions, prefix == currentWordPrefix,
            let first = suggestions.first
        else { return }
        let defaultIndex = suggestions.firstIndex(where: \.isDefault) ?? 0
        var held = [0: first]
        if !prefix.isEmpty { held[defaultIndex] = suggestions[defaultIndex] }

        // The model's words, then what the local tier had, so a model that
        // returned one usable word costs the user a slot rather than leaving a
        // gap.
        //
        // **Every held word is in `seen` before the first slot is filled, not as
        // its own slot comes up.** Filling in order is only enough while the held
        // slots are a run from zero, which today they are — `defaultIndex` is 0 or
        // 1 and slot 0 is always held. That is a fact about `shouldAutocorrect` in
        // another file, and the cost of it changing is the same word twice in the
        // bar: the model returns something folding to the held default, it is
        // unseen at the free slot above, and the held copy lands underneath it.
        // Seeding the set makes that impossible here rather than elsewhere.
        let pool =
            words.map { Suggestion(text: $0, language: language) } + suggestions.dropFirst()
        var merged: [Suggestion] = []
        var seen = Set(held.values.map { SeedLanguageModel.fold($0.text) })
        for slot in suggestions.indices {
            // `continue`, not `break`: a pool with nothing left for a free slot
            // must not take the held slots under it down with it, because the
            // held default is the one thing this function exists to protect.
            // `markDefault` clamps, so a short list still bolds it.
            guard
                let choice = held[slot]
                    ?? pool.first(where: { !seen.contains(SeedLanguageModel.fold($0.text)) })
            else { continue }
            seen.insert(SeedLanguageModel.fold(choice.text))
            merged.append(choice)
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
        clearRevertibleEdit()
        // Text in, so it sounds like text going in. Tapping a candidate is the
        // one insertion that reaches the document without a `KeyCap` behind it,
        // and `press(_:)` is where every other one gets its click.
        Feedback.keyClick(.tock)
        replaceCurrentWord(with: suggestion.text)
        learnWordJustCommitted()
        target?.insertText(" ")
        refreshSuggestions()
        reportInteraction(.suggestion)
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
