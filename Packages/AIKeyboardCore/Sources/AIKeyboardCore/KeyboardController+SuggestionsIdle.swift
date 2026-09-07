import Foundation

extension KeyboardController {
    func performIdleTyping() {
        guard idleTypingMayRun else { return }
        let prefix = currentWordPrefix
        guard !prefix.isEmpty else { return }
        let complete = store.storedCompleteOnIdle
        let space = store.storedSpaceOnIdle
        guard complete || space else { return }

        if complete, completesGroupedIdleTyping(space: space) { return }
        guard complete,
            !isCorrectingWordByHand,
            store.storedPredictions,
            !undoneAutocorrectSpellings.contains(SeedLanguageModel.fold(prefix)),
            let candidate = idleCompletion(for: prefix)
        else {
            if space { insertSpace() }
            return
        }
        if space {
            apply(candidate, learningSource: .automatic)
        } else {
            applyIdleCompletion(candidate)
        }
    }

    private func completesGroupedIdleTyping(space: Bool) -> Bool {
        guard grouped.isTyping else { return false }
        let level = groupingLevel
        let decoded = grouped.decoder(
            language: language, level: level, personal: personalWordsForDecoding
        ).decode(
            matching: grouped.code(language: language, level: level),
            pinnedTo: grouped.pins,
            completions: .afterExact)
        guard let longer = decoded.idleCompletion else {
            if space { insertSpace() }
            return true
        }
        let guess = grouped.cased(longer, in: language)
        let after = contextAfter
        Feedback.keyPress()
        Feedback.keyClick(.tock)
        clearRevertibleEdit()
        writeGroupedGuess(guess)
        closeGroupedIfCurrentWord()
        if !consumeGroupedSkipLearn() { recordCommittedWord(SuggestionEngine.wordCore(guess)) }
        if space {
            insertCommittalSpace(after: after)
            lastLearnedFolded = nil
        }
        deletedWordPrefix = nil
        refreshSuggestions()
        clearIdleTypingTask()
        reportInteraction(.suggestion)
        return true
    }

    private func applyIdleCompletion(_ candidate: Suggestion) {
        Feedback.keyPress()
        Feedback.keyClick(.tock)
        endGroupedWord()
        guard replaceCurrentWord(with: candidate.text) else {
            cancelRefinement()
            refreshSuggestions()
            return
        }
        recordCommittedWord(SuggestionEngine.wordCore(candidate.text), source: .automatic)
        deletedWordPrefix = nil
        refreshSuggestions()
        clearIdleTypingTask()
        reportInteraction(.suggestion)
    }

    private func clearIdleTypingTask() {
        idleTypingTask?.cancel()
        idleTypingTask = nil
        idleTypedAt = nil
        idleTypingPosition = nil
    }
}
