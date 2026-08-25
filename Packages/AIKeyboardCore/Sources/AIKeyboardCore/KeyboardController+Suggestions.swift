extension KeyboardController {

    // MARK: Suggestions

    /// Everything an answer from `SuggestionEngine.suggestions` depends on.
    ///
    /// Every argument that call takes except `personal`, which is a reference
    /// rather than a value and is stood in for by `vocabulary` — see
    /// `KeyboardController.lastSuggestionQuery` for why this exists at all and
    /// what bumps that counter. A field added to the engine's signature belongs
    /// here too, or the memo starts answering a question it was never asked.
    struct SuggestionQuery: Equatable {
        let prefix: String
        let context: String
        let languages: [KeyboardLanguage]
        let supplementary: [String]
        let autocorrect: AutocorrectLevel
        let vocabulary: Int
    }

    /// - Parameter schedulingRefinement: Whether a fresh answer may arm the
    ///   async tier's 300ms clock. **Off only from `KeyboardController.init`**,
    ///   which otherwise paid a model call before the first frame drew on every
    ///   single construction — not every keystroke, construction — because
    ///   `askForRefinement` cannot tell "the document already had a word in it"
    ///   from "the user just paused mid-sentence". Every other caller wants the
    ///   default: a keystroke that does not restart the clock is a keystroke the
    ///   model never gets asked about.
    public func refreshSuggestions(schedulingRefinement: Bool = true) {
        // **Above the Predictions guard, because it is not about predictions.**
        // Fix and Rewrite are drawn disabled on an empty field, and this is what
        // their keys redraw from; leaving it under the guard would freeze both keys
        // in whatever state they were in for anyone who has turned the suggestion
        // bar off. This function is the one thing every document change already
        // goes through, including the host's own `textDidChange`.
        let hadText = documentHasText
        refreshDocumentState()
        // **The host can move focus without the keyboard going away**, and
        // `viewWillAppear` does not fire for that — these callbacks
        // (`textDidChange` and `selectionDidChange`) are the only news of it a
        // keyboard extension gets. Whether they *always* arrive on a swap is not
        // something this repo can prove without a device, so this is additive: the
        // appearance path is still the guaranteed one, and a swap this misses
        // simply leaves the previous field's shape, which is what shipped. It is
        // safe on the keystroke path because it acts only on a trait that
        // *changed*, and a field being typed into reports the same one every time.
        // Ahead of the scoring below, so a language it switches is the language the
        // candidates come from rather than one refresh behind.
        adoptFieldKeyboardType(force: false)
        expirePendingAutocorrectUndoIfCaretMoved()
        stopDictationIfHostSent(hadText: hadText)
        // The field already holds the decoder's guess. Scoring that as typed
        // text replaces the grouped bar and lets space commit a third word.
        if grouped.isTyping {
            dropIdleTypingIfStale()
            return
        }
        guard store.storedPredictions else {
            suggestions = []
            dropIdleTypingIfStale()
            return
        }
        // A whole word the host has selected is scored in place of the word
        // behind the cursor — with a range selected there is nothing being typed,
        // and `documentContextBeforeInput` stops in front of the selection, so
        // the two never overlap. See `selectedWord`, which costs one `selectedText`
        // read and nothing else when there is no selection.
        let before = contextBefore
        // Held rather than re-read: every one of these is a call into the host,
        // this function runs on every keystroke, and the local tier's whole
        // budget is about a millisecond.
        let typed = currentWordPrefix
        let selected = selectedWord
        let prefix = selected ?? typed
        // Everything in front of what is being scored. A selection is not part of
        // the before-context at all, and `selectedWord` refuses one with a word
        // joined to its leading end, so this drops nothing in that case.
        let context = String(before.dropLast(typed.count))
        let languages = [language] + store.storedEnabledLanguages.filter { $0 != language }
        let supplementary = store.storedPersonalDictionary + supplementaryWords
        let level = store.storedAutocorrectLevel
        let query = SuggestionQuery(
            prefix: prefix, context: context, languages: languages,
            supplementary: supplementary, autocorrect: level, vocabulary: vocabularyVersion)
        let results: [Suggestion]
        if query == lastSuggestionQuery {
            results = lastSuggestionResults
        } else {
            results = SuggestionEngine.suggestions(
                prefix: prefix,
                context: context,
                languages: languages,
                supplementary: supplementary,
                personal: personal,
                autocorrect: level
            )
            lastSuggestionQuery = query
            lastSuggestionResults = results
        }
        // **Compared before it is assigned, and that is a separate saving from the
        // memo above.** `@Published` emits on assignment and never on change, so
        // the second and third refresh of a keystroke each republished the same
        // three words and each rebuilt every key. `Suggestion`'s equality is
        // deliberately text, language and the bold flag rather than its `id` —
        // see `.claude/rules/suggestion-bar.md`, where that is what stops the bar
        // fading on every letter — so this asks exactly the question the bar
        // draws from.
        let bar = pinningDefaultToTypedIfNeeded(results, prefix: prefix)
        if bar != suggestions { suggestions = bar }
        // **Not for a selection.** The async tier predicts what somebody typing
        // is about to type, and nobody is typing; `applyRefinement` would drop
        // the answer anyway, because the prefix it hands back is not
        // `currentWordPrefix`.
        //
        // **A request already in flight has to be cancelled here, not merely
        // skipped.** A space arms the clock on an empty prefix, and a double tap
        // that selects a word moments later takes this branch and used to leave
        // the old request running: `applyRefinement`'s only staleness gate was
        // `prefix == currentWordPrefix`, and an empty prefix asked before the
        // selection still equals the empty prefix a selection reads, so the
        // model's guess landed in the bar over a word the user had just pointed
        // at. See the `selection == nil` guard on `applyRefinement` itself, which
        // is what actually closes it — this cancel only stops paying for an
        // answer nothing can use any more.
        if selected == nil {
            if schedulingRefinement { askForRefinement(prefix: prefix, context: context) }
        } else {
            refiner?.cancel()
        }
        dropIdleTypingIfStale()
    }

    /// When space cannot commit a correction, the bold slot has to be the typed
    /// word, or the bar advertises a swap that will not happen. Two reasons it
    /// is not allowed: Autocorrect is off, or the user is backspacing through
    /// this word. Next-word suggestions (empty prefix) are never auto-committed
    /// anyway; leave their middle bold alone.
    ///
    /// **A correction the level refused is not one of the two, and must not be
    /// handled here.** `AutocorrectLevel.confident` is a floor on
    /// `CommitReason.confidence`, and the reason only exists inside
    /// `SuggestionEngine.suggestions`, which has already pinned slot 0 before
    /// this sees the array. Re-deriving that decision from `store` would be a
    /// second, worse copy of a rule that reads evidence this function cannot
    /// see.
    ///
    /// **A selection has no default at all, which is a third answer rather than
    /// a harder version of the second.** Over a range the space bar types a
    /// space, the way it does on the system keyboard (`insertSpace` refuses the
    /// commit there), so no candidate is "inserted when you press space" and
    /// none may be drawn as if it were. Pinning slot 0 the way the other two
    /// reasons do would not do that job here: slot 0 *is* the selected word, so
    /// under any rule that draws the default it comes back at the user, bold, in
    /// the middle slot. The word is already in the field and highlighted in it;
    /// the bar's three slots are for the words that could take its place.
    ///
    /// **The selection strip runs before the empty-prefix guard, and it used to
    /// run after it.** `prefix` is `selectedWord ?? currentWordPrefix`, and both
    /// can be empty over a real selection — a partial-word selection, or a whole
    /// word selected together with its trailing space — so the old order let a
    /// live selection fall straight through the `!prefix.isEmpty` guard and keep
    /// whatever bold default the empty-prefix (next-word) tier had drawn, hint
    /// and all. Any selection loses every default; whether the *prefix* is empty
    /// decides nothing about that.
    private func pinningDefaultToTypedIfNeeded(
        _ results: [Suggestion], prefix: String
    )
        -> [Suggestion]
    {
        if selection != nil {
            return results.map { Suggestion(text: $0.text, language: $0.language) }
        }
        guard !prefix.isEmpty else { return results }
        // **The spelling the user already undid this session is a third reason,
        // beside Autocorrect-off and a hand repair.** `insertSpace` refuses to
        // put the same swap back (`undoneAutocorrectSpellings`), so a bar that
        // still bolds the correction is advertising a commit space will not make.
        // Folded, the same way the set itself is keyed.
        if store.storedAutocorrectLevel == .off || isCorrectingWordByHand
            || undoneAutocorrectSpellings.contains(SeedLanguageModel.fold(prefix))
        {
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
    /// The second fact is that an edit can only be taken back while what it wrote
    /// is still standing where it wrote it. **This is the whole of the undo's
    /// lifetime now**, and it used to be one line of it: the revert was cleared by
    /// every keystroke and this only caught the case no keystroke covers, a host
    /// emptying the field because the message was sent. Both are one question
    /// asked of the document — an empty field cannot contain what the edit wrote —
    /// and asking it here rather than at each keystroke is what lets the undo
    /// survive typing without any path having to remember to keep it alive.
    /// Ordered after the flag so it reads the fresh answer, and safe to run from
    /// inside `replaceTargetText` — `applyDirectly` and `insertClip` both record
    /// the edit *after* that call returns, so this can never delete the edit that
    /// is being made.
    public func refreshDocumentState() {
        let hadText = documentHasText
        // Assigned only when it moved, for the reason `revertibleEdit` on the next
        // line already is: `@Published` emits on assignment and never on change,
        // and this runs two or three times per keystroke while answering the same
        // `true` every time after the first character. Every one of those emissions
        // was a rebuild of the whole keyboard. The value is identical either way,
        // so the `hadText` comparison below reads exactly what it always did.
        let hasText = hasTextToWorkWith
        if hasText != documentHasText { documentHasText = hasText }
        expireRevertibleEditIfUnusable()
        // Send, or switching to an empty chat, with the keyboard still up.
        // Appear is not guaranteed. Only the *transition* onto empty, because
        // `insertText` then immediately reading the proxy can still look empty,
        // and resetting there would undo the Hebrew we just announced.
        if hadText, !documentHasText { announceHostLanguage(language) }
        adoptOpenWord()
    }

    /// Keep the word under the cursor, and commit it if the host just emptied
    /// the field. Chat Send is that empty: it never presses space, `textDidChange`
    /// is the news, and without this the last word of the message is lost.
    ///
    /// A delete that erases the whole word is the other empty, and must not
    /// count: `deletedWordPrefix` is `""` then, not nil.
    ///
    /// **The document actually being empty is the trigger, not the prefix being
    /// empty.** This runs on every keystroke and every caret move, and a caret
    /// tapped to *any* word boundary in a non-empty document reads as an empty
    /// prefix — `"hello| world"` no less than `""`. Committing `openWord` there
    /// taught a word the user had only repositioned past, not finished; Send is
    /// the one case this is actually for, and Send is the one case that leaves
    /// `documentHasText` false. `refreshDocumentState` sets it just above this
    /// call, so it is already the fresh answer.
    func adoptOpenWord() {
        // The field holds a decoder guess, not a word the user typed. Stashing
        // it here is how Chat Send and the space after `textDidChange` taught
        // the guess even when skip-learn ran.
        if grouped.isTyping, !grouped.allLettersPinned {
            openWord = ""
            return
        }
        let raw = currentWordPrefix
        let word = SuggestionEngine.wordCore(raw)
        if word.isEmpty {
            if !openWord.isEmpty, deletedWordPrefix == nil, !documentHasText {
                recordCommittedWord(openWord, permittedOverride: openWordPermitted)
            }
            openWord = ""
            return
        }
        if Self.wordAlreadyTerminated(raw, core: word) {
            openWord = ""
            return
        }
        // **A caret parked inside a word is not the word being typed.**
        // `currentWordPrefix` is only ever the run behind the caret, so
        // `"wor|ld"` reaches here as `"wor"` — a fragment, not the word standing
        // in the field. Adopting it would teach half a word the moment somebody
        // taps back into one they already finished; refuse rather than overwrite,
        // and whatever this slot already held (the word actually last finished
        // being typed) stays. Same test `selectedWord` applies at its trailing
        // end, `KeyboardController+TextEditing.swift`.
        if let next = contextAfter.first,
            next.isLetter || next.isNumber || KeyboardController.staysInsideWord(next)
        {
            return
        }
        openWord = word
        // Captured now, while `target` is still the field these letters were
        // typed into — see `openWordPermitted`.
        openWordPermitted = SecureField.permitsRead(
            secure: target?.isSecureTextEntry ?? nil, contentType: fieldContentType)
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
                // Only a live session, and only the real capture path — never the
                // scripted demo `MockScreenContext` plays, which is the right thing
                // to show on a marketing screen and the wrong thing to predict a
                // real reply from. `FeatureFlags.screenCaptureReply` is what makes
                // that a fact rather than a hope: with it off, `ScreenContextSession
                // .shared.isLive` is unreachable here in a shipping build at all
                // (`startConsuming` is gated on the same flag, so nothing ever
                // writes `.watching` / `.ready` into this process's session), and
                // this reads the flag explicitly so every reader of the held
                // feature is gated alike rather than relying on that as an accident
                // of what else is wired up.
                screenContext: FeatureFlags.screenCaptureReply && ScreenContextSession.shared.isLive
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
    ///
    /// **`selection == nil` is its own guard, and `prefix == currentWordPrefix`
    /// cannot stand in for it.** A next-word request is armed on an empty
    /// prefix, `refreshSuggestions` skips asking again the moment a selection
    /// exists but the request already in flight keeps running, and
    /// `currentWordPrefix` is unaffected by a selection at all — so the answer
    /// can arrive with `prefix` and `currentWordPrefix` both still `""` while a
    /// word sits selected, and the staleness gate alone would wave it through
    /// onto a selection's correction candidates.
    func applyRefinement(_ words: [String], for prefix: String) {
        guard store.storedPredictions, selection == nil, prefix == currentWordPrefix,
            let first = suggestions.first
        else { return }
        let pool =
            words.map { Suggestion(text: $0, language: language) } + suggestions.dropFirst()
        // Slot 0 is always the typed keystrokes, never anything from `pool`.
        var merged: [Suggestion] = [first]
        var seen = Set([SeedLanguageModel.fold(first.text)])
        // The same shape the local tier returns: the typed echo plus one offer per
        // drawn slot. Fixed at three here, this was the one path that could shrink
        // the bar back to two candidates the moment the refiner answered.
        for candidate in pool {
            guard merged.count < SuggestionEngine.barSlots + 1 else { break }
            let folded = SeedLanguageModel.fold(candidate.text)
            guard !seen.contains(folded) else { continue }
            seen.insert(folded)
            merged.append(candidate)
        }
        let modelFolds = Set(words.map(SeedLanguageModel.fold))
        let defaultIndex =
            merged.firstIndex { modelFolds.contains(SeedLanguageModel.fold($0.text)) } ?? 0
        // **Guarded the same way `refreshSuggestions` guards its own publish.**
        // A cache hit answers synchronously, so a keystroke that fires two or
        // three refreshes could fire the refiner that many times too, and
        // without this every one of them republished the bar — a rebuild of
        // every key — even when the merge reproduced exactly what was already
        // on screen. `Suggestion.==` is text, language and the bold flag, the
        // same equality `refreshSuggestions` already trusts.
        let bar = pinningDefaultToTypedIfNeeded(
            SuggestionEngine.markDefault(merged, at: defaultIndex), prefix: prefix)
        if bar != suggestions { suggestions = bar }
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
            guard
                SuggestionEngine.comparable(self.currentWordPrefix)
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

        if grouped.isTyping, complete {
            let level = groupingLevel
            let decoder = grouped.decoder(
                language: language, level: level, personal: personalWordsForDecoding)
            let decoded = decoder.decode(
                matching: grouped.code(language: language, level: level),
                pinnedTo: grouped.pins,
                completions: .afterExact)
            if let longer = decoded.idleCompletion {
                let guess = grouped.cased(longer, in: language)
                // Read before `writeGroupedGuess` mutates the field, for the
                // reason `apply`'s own read is. See `insertCommittalSpace`.
                let after = contextAfter
                Feedback.keyPress()
                Feedback.keyClick(.tock)
                // **Grouped typing is the one writer that still clears the way
                // back outright**, here and in `pressGroupedKey`. Everything else
                // leaves it to `expireRevertibleEditIfUnusable`, which runs from
                // `refreshDocumentState` — and a grouped guess is written by
                // `writeGroupedGuess`, which rewrites the word in the field
                // without going through `refreshSuggestions` at all. An expiry
                // that is never asked is not an expiry.
                clearRevertibleEdit()
                writeGroupedGuess(guess)
                closeGroupedIfCurrentWord()
                if !consumeGroupedSkipLearn() {
                    recordCommittedWord(SuggestionEngine.wordCore(guess))
                }
                if space {
                    insertCommittalSpace(after: after)
                    lastLearnedFolded = nil
                }
                deletedWordPrefix = nil
                refreshSuggestions()
                idleTypingTask?.cancel()
                idleTypingTask = nil
                idleTypedAt = nil
                reportInteraction(.suggestion)
                return
            }
            if space { insertSpace() }
            return
        }

        // **The spelling the user already undid this session is refused here
        // too, not only on the space bar.** `idleCompletion` picks the first
        // offer that is not the literal keystrokes, with no idea that this exact
        // prefix is the one `undoAutocorrectIfPending` was just asked to put
        // back — so completing on pause could silently re-run the swap
        // `insertSpace` already knows to refuse, from a different call site.
        if complete, !isCorrectingWordByHand, store.storedPredictions,
            !undoneAutocorrectSpellings.contains(SeedLanguageModel.fold(prefix)),
            let candidate = idleCompletion(for: prefix)
        {
            if space {
                apply(candidate)
            } else {
                Feedback.keyPress()
                Feedback.keyClick(.tock)
                endGroupedWord()
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
    ///
    /// **A candidate an automatic path may not write is skipped, not merely
    /// refused.** This fires with no tap between the pause and
    /// `replaceCurrentWord` — `performIdleTyping` calls it directly, or through
    /// `apply`, which does the same insert — so it is a second automatic path
    /// to the document and `commitReason`'s guard never runs in front of it. A
    /// learned email at three sightings, typed as far as its local part, ranks
    /// `.learned` — the second-highest tier a mid-word candidate reaches — so
    /// without this it was exactly what "first suggestion that is not the
    /// typed word" picked, pasted on a pause with nothing to undo. Falling
    /// through to the next candidate, rather than refusing outright, is what
    /// keeps an ordinary completion sitting behind it from being held back by
    /// a personal token it has nothing to do with; a bar with nothing left
    /// answers nil, same as an empty prefix. `SuggestionEngine.isAutomaticallyInsertable`
    /// is the identical question `commitReason` asks of its own winner, so the
    /// two doors read one definition rather than two that can drift.
    func idleCompletion(for prefix: String) -> Suggestion? {
        let typed = SuggestionEngine.comparable(prefix)
        guard !typed.isEmpty else { return nil }
        return suggestions.first {
            SuggestionEngine.comparable($0.text) != typed
                && SuggestionEngine.isAutomaticallyInsertable($0.text)
        }
    }

    /// A credential field, a recording, a selection, or the emoji panel: none
    /// of those is a pause in ordinary typing. Grouped typing is allowed only
    /// when Complete on pause is on; space-on-idle alone does not arm it.
    ///
    /// A hand repair is not in this list. Space on pause has to fire after
    /// backspace; `performIdleTyping` skips completing the word, and
    /// `insertSpace` already skips autocorrect, so the letters they kept stay.
    private var idleTypingMayRun: Bool {
        guard overlay == .none, !isDictating, selection == nil else { return false }
        if grouped.isTyping, !store.storedCompleteOnIdle { return false }
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
        // Text in, so it sounds like text going in. Tapping a candidate is the
        // one insertion that reaches the document without a `KeyCap` behind it,
        // and `press(_:)` is where every other one gets its click.
        Feedback.keyClick(.tock)
        endGroupedWord()
        // Read before the replacement, because it is the replacement that clears
        // the selection — and, for `contextAfter`, because it is also the
        // replacement that can leave the proxy reporting stale context for a
        // moment. See `insertCommittalSpace`.
        let overSelectedWord = selectedWord != nil
        // **Any range selection, not only one `selectedWord` recognises.** A
        // multi-word or partial selection is neither a whole word (`selectedWord`
        // is nil for both) nor a plain caret, and `insertCommittalSpace`'s hop
        // is only safe for the caret — see the branch below.
        let hadSelection = selection != nil
        let after = contextAfter
        replaceCurrentWord(with: suggestion.text)
        // The candidate may already carry a mark (`hello,`). The space-bar path
        // skips a word that is already terminated so `hello.` + space does not
        // count twice; a tap is the first time this word is committed.
        recordCommittedWord(SuggestionEngine.wordCore(suggestion.text))
        if overSelectedWord {
            // **No space, because a selected word is repaired in place.** The
            // spacing around it is already in the field, and `I recieve it` would
            // come back `I receive  it`. Nothing is being finished here either:
            // the caret is sitting in the middle of somebody's sentence.
            //
            // A word picked over a selection is hand-placed, exactly as one
            // reached through the accents popup is, so the next space must not
            // overrule it — see `isCorrectingWordByHand`. Read out of the field
            // rather than taken from the candidate, because `replaceCurrentWord`
            // may have given it back a mark the candidate did not carry.
            deletedWordPrefix = currentWordPrefix
        } else if hadSelection {
            // **A multi-word or partial selection is repaired in place too, and
            // the pin is the same as a selected word's: touch nothing outside
            // it.** Byte-identical to what this branch always did — a range
            // this shape gets an unconditional space, even when one already
            // follows it (`say ⟦hello world.⟧ now` tapping `the` is pinned to
            // `say the  now`, the second space and all). `insertCommittalSpace`'s
            // hop does not apply here: the after-caret text belongs to whatever
            // sits past the selection, not to a word this tap just finished, and
            // whether a range selection may ever touch what is outside it is a
            // design question this fix does not reopen.
            target?.insertText(" ")
            lastLearnedFolded = nil
            deletedWordPrefix = nil
        } else {
            insertCommittalSpace(after: after)
            lastLearnedFolded = nil
            // Committed on purpose, so the hand repair this word may have been
            // under is over — the same line `insertSpace` ends on, for the same
            // reason.
            deletedWordPrefix = nil
        }
        pendingAutocorrectUndo = nil
        refreshSuggestions()
        reportInteraction(.suggestion)
    }

    /// Finish a word with a space, or step over one that is already sitting
    /// in front of the caret.
    ///
    /// **A tap used to insert a second space beside one that was already
    /// there.** `"The teh| quick"` (`|` the caret) committed as
    /// `"The the  quick"` — stock iOS instead replaces the word and moves the
    /// caret past the space already doing that job. `contextAfter` has to be
    /// read by the caller *before* the replacement runs and handed in here,
    /// because this keyboard's own delete-then-insert can leave a proxy
    /// reporting stale context for a moment right after a write it just made
    /// itself — the same staleness `deleteBackward(utf16Units:)` already
    /// re-reads around.
    ///
    /// **Only a literal U+0020, never anything `isWhitespace` calls
    /// equivalent.** A newline starts the next line rather than sitting in
    /// the gap this word is finishing into, and hopping over it would leave
    /// the caret a line down from where the user is looking. A non-breaking
    /// space was placed on purpose by somebody else, not by this keyboard's
    /// own spacing, so it is left standing and a plain space still goes in
    /// beside it.
    ///
    /// **The space bar does not call this.** `insertSpace` always writes a
    /// literal space: `pendingAutocorrectUndo` remembers "the replacement
    /// plus the space that follows it", and a hop there would leave the undo
    /// eating a space the user pressed themselves rather than the one a tap
    /// would have inserted.
    func insertCommittalSpace(after contextAfter: String) {
        guard contextAfter.first == " " else {
            target?.insertText(" ")
            return
        }
        target?.adjustTextPosition(byCharacterOffset: 1)
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
                recordCommittedWord(openWord, permittedOverride: openWordPermitted)
            }
            return
        }
        if Self.wordAlreadyTerminated(raw, core: word) { return }
        // **The same continues-past-caret refusal `adoptOpenWord` needs.** Every
        // caller here is about to insert a terminator (space, Return, a mark) at
        // the caret, and the caret is not always at the true end of the word it
        // sits in — Return or a punctuation key pressed inside existing text
        // splits it, `"hel|lo"` reaching here as `"hel"`. Learning that fragment
        // writes half a word into the personal dictionary as if it were whole.
        if let next = contextAfter.first,
            next.isLetter || next.isNumber || KeyboardController.staysInsideWord(next)
        {
            return
        }
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
    ///
    /// - Parameter permittedOverride: The permission decided when the word was
    ///   adopted, for a caller committing `openWord` rather than the word just
    ///   typed. **`target` may already be a different document by the time this
    ///   runs** — iOS keeps one extension instance across fields and across host
    ///   apps, and `openWord` can outlive the field it was typed in when it is
    ///   never finished with a space or a Return there. Re-deriving permission
    ///   from `target` at commit time would judge a word typed in a credential
    ///   field by whatever field the keyboard has moved on to. Nil for every
    ///   other caller, which is committing a word `target` still is the field
    ///   for.
    func recordCommittedWord(_ word: String, permittedOverride: Bool? = nil) {
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
        let permitted =
            permittedOverride
            ?? SecureField.permitsRead(
                secure: target?.isSecureTextEntry ?? nil, contentType: fieldContentType)
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
            // screen" have the same answer for a password. Learning itself is
            // always on; the only refusal left is a credential field.
            permitted: permitted
        )
        // **Cleared regardless of `wrote`.** A refusal is a decision, not a
        // deferral: leaving `openWord` standing after a refused write is what let
        // it be offered again under a later document's permission instead of the
        // one it was actually typed under.
        openWord = ""
        if wrote {
            lastLearnedFolded = folded
            // The one thing that changes an answer without changing the question.
            // See `lastSuggestionQuery`.
            vocabularyVersion &+= 1
        }
    }
}
