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
            dropIdleTypingIfStale()
            return
        }
        let prefix = currentWordPrefix
        let before = contextBefore
        let context = prefix.isEmpty ? before : String(before.dropLast(prefix.count))
        let results = SuggestionEngine.suggestions(
            prefix: prefix,
            context: context,
            languages: [language] + store.storedEnabledLanguages.filter { $0 != language },
            supplementary: store.storedPersonalDictionary + supplementaryWords,
            personal: personal
        )
        suggestions = pinningDefaultToTypedIfNeeded(results, prefix: prefix)
        askForRefinement(prefix: prefix, context: context)
        dropIdleTypingIfStale()
    }

    /// When space cannot commit a correction, the bold slot has to be the typed
    /// word, or the bar advertises a swap that will not happen. Two reasons it
    /// is not allowed: Autocorrect is off, or the user is backspacing through
    /// this word. Next-word suggestions (empty prefix) are never auto-committed
    /// anyway; leave their middle bold alone.
    private func pinningDefaultToTypedIfNeeded(
        _ results: [Suggestion], prefix: String
    )
        -> [Suggestion]
    {
        if !prefix.isEmpty, !store.storedAutocorrect || isCorrectingWordByHand {
            return SuggestionEngine.markDefault(results, at: 0)
        }
        return results
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
        adoptOpenWord()
    }

    /// Keep the word under the cursor, and commit it if the host just emptied
    /// the field. Chat Send is that empty: it never presses space, `textDidChange`
    /// is the news, and without this the last word of the message is lost.
    ///
    /// A delete that erases the whole word is the other empty, and must not
    /// count: `deletedWordPrefix` is `""` then, not nil.
    func adoptOpenWord() {
        let raw = currentWordPrefix
        let word = SuggestionEngine.wordCore(raw)
        if word.isEmpty {
            if !openWord.isEmpty, deletedWordPrefix == nil {
                recordCommittedWord(openWord)
            }
            openWord = ""
            return
        }
        if Self.wordAlreadyTerminated(raw, core: word) {
            openWord = ""
            return
        }
        openWord = word
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
                    secure: target?.isSecureTextEntry ?? nil, contentType: fieldContentType)))
    }

    /// Put the model's words into the bar.
    ///
    /// Slot 0 stays the typed keystrokes, so the user can always keep what they
    /// keyed. When Autocorrect is on, the first model word becomes default.
    /// When it is off (or the user is repairing this word by hand), default
    /// stays on the typed word so the bar does not advertise a swap space will
    /// not make. The model's words still fill the other slots for a tap.
    ///
    /// It never applies to a document that has moved on. The prefix is the one
    /// handed back from the callback, not re-read here against itself.
    func applyRefinement(_ words: [String], for prefix: String) {
        guard store.storedPredictions, prefix == currentWordPrefix,
            let first = suggestions.first
        else { return }
        let held = [0: first]
        let pool =
            words.map { Suggestion(text: $0, language: language) } + suggestions.dropFirst()
        var merged: [Suggestion] = []
        var seen = Set(held.values.map { SeedLanguageModel.fold($0.text) })
        for slot in 0..<3 {
            guard
                let choice = held[slot]
                    ?? pool.first(where: { !seen.contains(SeedLanguageModel.fold($0.text)) })
            else { continue }
            seen.insert(SeedLanguageModel.fold(choice.text))
            merged.append(choice)
        }
        let modelFolds = Set(words.map(SeedLanguageModel.fold))
        let defaultIndex =
            merged.firstIndex { modelFolds.contains(SeedLanguageModel.fold($0.text)) } ?? 0
        suggestions = pinningDefaultToTypedIfNeeded(
            SuggestionEngine.markDefault(merged, at: defaultIndex), prefix: prefix)
    }

    /// Restart the pause that can finish a word or add a space.
    ///
    /// **Armed from a keystroke, not from a suggestion refresh.** A caret tap,
    /// the keyboard coming on screen over a half-typed word, a language switch
    /// and the host's own `textDidChange` all call `refreshSuggestions`, and
    /// none of those is the user stopping typing. Starting the wait there
    /// inserted a space 300 ms after a tap into someone else's word. The wait
    /// is `storedIdleDelayMs`, read at the keystroke, not the 300 ms that ships.
    func noteTypedInput() {
        let prefix = currentWordPrefix
        let typedAt = ContinuousClock.now
        idleTypedAt = typedAt
        scheduleIdleTyping(armedPrefix: prefix, typedAt: typedAt)
    }

    /// Cancel the pause when it can no longer apply. Does not start one: that
    /// is `noteTypedInput`'s job, so a refresh cannot spend a pause nobody
    /// typed into.
    func dropIdleTypingIfStale() {
        let prefix = currentWordPrefix
        let armed = store.storedCompleteOnIdle || store.storedSpaceOnIdle
        if prefix.isEmpty || !armed || !idleTypingMayRun {
            idleTypingTask?.cancel()
            idleTypingTask = nil
            idleTypedAt = nil
        }
    }

    func scheduleIdleTyping(armedPrefix: String, typedAt: ContinuousClock.Instant) {
        idleTypingTask?.cancel()
        idleTypingTask = nil
        guard store.storedCompleteOnIdle || store.storedSpaceOnIdle else { return }
        guard !armedPrefix.isEmpty else { return }
        guard idleTypingMayRun else { return }
        let delay = store.storedIdleDelayMs
        idleTypingTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(delay))
            } catch {
                return
            }
            guard !Task.isCancelled, let self else { return }
            // A later keystroke replaced `idleTypedAt` and armed a new wait.
            // Cancellation should have dropped this task; this is the lock
            // behind that door, so a swallowed cancel cannot insert a space
            // from the first letter of the word.
            guard self.idleTypedAt == typedAt else { return }
            // A tap in the host field moved the caret onto a different word
            // without a key. The pause belonged to `armedPrefix`.
            guard SuggestionEngine.comparable(self.currentWordPrefix)
                == SuggestionEngine.comparable(armedPrefix)
            else { return }
            self.performIdleTyping()
        }
    }

    /// The pause fired. Completing the word and adding a space are separate
    /// switches; both on is the completion plus a space.
    func performIdleTyping() {
        guard idleTypingMayRun else { return }
        let prefix = currentWordPrefix
        guard !prefix.isEmpty else { return }
        let complete = store.storedCompleteOnIdle
        let space = store.storedSpaceOnIdle
        guard complete || space else { return }

        if complete, store.storedPredictions, let candidate = idleCompletion(for: prefix) {
            if space {
                apply(candidate)
            } else {
                Feedback.keyPress()
                Feedback.keyClick(.tock)
                clearRevertibleEdit()
                replaceCurrentWord(with: candidate.text)
                recordCommittedWord(SuggestionEngine.wordCore(candidate.text))
                deletedWordPrefix = nil
                refreshSuggestions()
                // The word is finished. A wait still running from the letters
                // that just became this word must not fire again (`hellos`
                // after `hello`).
                idleTypingTask?.cancel()
                idleTypingTask = nil
                idleTypedAt = nil
                reportInteraction(.suggestion)
            }
            return
        }
        if space { insertSpace() }
    }

    /// Complete on pause writes the first suggestion that is not the typed
    /// word, not the bold slot. Mid-word the engine leaves the keystrokes as
    /// default unless it is sure they are a typo, and Autocorrect-off remakes
    /// default to slot 0 so space will not swap. The completion is still
    /// sitting in slot 1. Taking `isDefault` made this switch a no-op.
    func idleCompletion(for prefix: String) -> Suggestion? {
        let typed = SuggestionEngine.comparable(prefix)
        guard !typed.isEmpty else { return nil }
        return suggestions.first { SuggestionEngine.comparable($0.text) != typed }
    }

    /// A credential field, a recording, a hand repair, a selection, or the
    /// emoji panel: none of those is a pause in ordinary typing.
    private var idleTypingMayRun: Bool {
        guard overlay == .none, !isDictating, !isCorrectingWordByHand, selection == nil else {
            return false
        }
        return SecureField.permitsRead(
            secure: target?.isSecureTextEntry ?? nil, contentType: fieldContentType)
    }

    /// Drop anything the async tier or the idle pause is waiting on. Called as
    /// the keyboard goes away; an answer that arrives afterwards would land in
    /// the next document.
    public func cancelRefinement() {
        refiner?.cancel()
        idleTypingTask?.cancel()
        idleTypingTask = nil
        idleTypedAt = nil
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
        // The candidate may already carry a mark (`hello,`). The space-bar path
        // skips a word that is already terminated so `hello.` + space does not
        // count twice; a tap is the first time this word is committed.
        recordCommittedWord(SuggestionEngine.wordCore(suggestion.text))
        target?.insertText(" ")
        lastLearnedFolded = nil
        // Committed on purpose, so the hand repair this word may have been under is
        // over — the same line `insertSpace` ends on, for the same reason.
        deletedWordPrefix = nil
        refreshSuggestions()
        reportInteraction(.suggestion)
    }

    /// Remember the word still under the cursor, and the pair it makes with the
    /// one before it.
    ///
    /// **The word under the cursor, not the last token of the document.** A
    /// trailing space means this word was already learned when that space was
    /// pressed. Reading `previousWords` instead re-taught `hello` every time the
    /// keyboard went away after `hello `, and never taught the last word of a
    /// message that was sent without a trailing space — which is how a chat
    /// Send button finishes a word, and how Return does. Tapping a candidate
    /// always inserts a space, so that path was the only one that reliably
    /// counted. Callers that insert a terminator (space, Return, a full stop)
    /// learn *before* the terminator lands, so the word is still under the
    /// cursor.
    ///
    /// A mark already after the word means it was finished when the mark was
    /// typed. Space after `hello.` must not count the same word twice.
    ///
    /// Three things can still stop a write, and each is somebody's explicit
    /// decision rather than a heuristic: the setting is off, the field is a
    /// credential field, or the App Group is out of reach because Full Access
    /// was never granted — in which case `PersonalLanguageModel` has nowhere to
    /// persist and quietly keeps its counts for as long as this keyboard
    /// instance lives.
    public func learnWordJustCommitted() {
        let raw = currentWordPrefix
        let word = SuggestionEngine.wordCore(raw)
        if word.isEmpty {
            if !openWord.isEmpty, deletedWordPrefix == nil {
                recordCommittedWord(openWord)
            }
            return
        }
        if Self.wordAlreadyTerminated(raw, core: word) { return }
        recordCommittedWord(word)
    }

    /// A mark after the core means the word was finished when the mark was typed.
    static func wordAlreadyTerminated(_ raw: String, core word: String) -> Bool {
        guard let core = raw.range(of: word, options: .backwards),
            core.upperBound < raw.endIndex
        else { return false }
        return raw[core.upperBound...].allSatisfy(\.isPunctuation)
    }

    /// The write itself. `learnWordJustCommitted` decides *whether* this word is
    /// still open; `apply` already knows it is committing.
    func recordCommittedWord(_ word: String) {
        guard !word.isEmpty else { return }
        let folded = SeedLanguageModel.fold(word)
        guard folded != lastLearnedFolded else { return }
        let words = SuggestionEngine.previousWords(in: contextBefore)
        let previous: String?
        if words.last.map({ SeedLanguageModel.fold($0) == folded }) == true {
            previous = words.count >= 2 ? words[words.count - 2] : nil
        } else {
            previous = words.last
        }
        let wrote = personal.record(
            word: word,
            previous: previous,
            // The word's own script, not the layout's. Somebody typing a Hebrew
            // sentence has the Hebrew layout up, and the English words inside it
            // belong in the English counters or `לעבודה` and `sprint` end up in one
            // list where neither can be looked up.
            language: SuggestionEngine.dominantLanguage(
                in: word, among: [language] + store.storedEnabledLanguages.filter { $0 != language })
                ?? language,
            // The same question `SecureField` answers for a screen read, asked
            // again here because "may I keep this word" and "may I send this
            // screen" have the same answer for a password.
            permitted: store.storedLearnsFromTyping
                && SecureField.permitsRead(
                    secure: target?.isSecureTextEntry ?? nil, contentType: fieldContentType)
        )
        if wrote {
            lastLearnedFolded = folded
            openWord = ""
        }
    }
}
