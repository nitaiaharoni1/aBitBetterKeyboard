import Foundation

extension KeyboardController {
    func insertSpace() {
        Feedback.keyPress()
        retirePendingAutocorrectUndo(.acceptLearning)
        if let query = lastSuggestionQuery, query.autocorrect != store.storedAutocorrectLevel {
            refreshSuggestions(schedulingRefinement: false)
        }
        closeGroupedIfCurrentWord()

        commitOrdinarySpace()
    }

    private func commitOrdinarySpace() {
        let original = currentWordPrefix
        let contextBeforeSwap = contextBefore
        let documentIdentifier = target?.documentIdentifier
        let permitted = SecureField.permitsRead(
            secure: target?.isSecureTextEntry ?? nil, contentType: fieldContentType)
        let swapped = automaticSpaceSwap(
            original: original, contextBeforeSwap: contextBeforeSwap, permitted: permitted)
        let skipLearning = consumeGroupedSkipLearn()
        if swapped == nil, !skipLearning {
            learnWordJustCommitted()
        } else if swapped != nil {
            openWord = ""
        }
        target?.insertText(" ")
        lastLearnedFolded = nil
        deletedWordPrefix = nil
        if let swapped {
            pendingAutocorrectUndo = PendingAutocorrectUndo(
                original: swapped.original, replacement: swapped.replacement,
                contextAfterSwap: String(contextBeforeSwap.dropLast(original.count)) + swapped.replacement
                    + " ",
                documentIdentifier: documentIdentifier, learnedCommit: swapped.learnedCommit,
                shouldLearn: !skipLearning)
        }
        // A `.words` field capitalises after every space; any other arms only
        // where a sentence just ended. The double-space full stop used to be the
        // one place `.sentences` armed on space, so typing `.` and then space
        // left the next sentence lowercase; that shortcut is gone (two spaces are
        // two spaces), and this is the boundary it stood in for.
        if autocapitalizationMode == .words || caretBeginsACapitalizedRun(mode: autocapitalizationMode) {
            armShiftAtBoundary()
        }
        refreshSuggestions()
    }

    private func automaticSpaceSwap(
        original: String, contextBeforeSwap: String, permitted: Bool
    ) -> (original: String, replacement: String, learnedCommit: LearnedCommit)? {
        guard store.storedAutocorrectLevel != .off,
            !isCorrectingWordByHand,
            selection == nil,
            let after = knownContextAfter,
            !Self.continuesWord(in: after),
            let candidate = suggestions.first(where: \.isDefault),
            candidate.commit == .contextual,
            !original.isEmpty,
            candidate.text.lowercased() != original.lowercased(),
            !undoneAutocorrectSpellings.contains(SeedLanguageModel.fold(original))
        else { return nil }
        let replacement = Self.restoringEdgeMarks(of: original, to: candidate.text)
        let previous = SuggestionEngine.previousWords(
            in: String(contextBeforeSwap.dropLast(original.count))
        ).last
        guard replaceCurrentWord(with: candidate.text) else { return nil }
        return (
            original,
            replacement,
            LearnedCommit(
                word: SuggestionEngine.wordCore(replacement), previous: previous,
                language: candidate.language, permitted: permitted, source: .automatic)
        )
    }
}
