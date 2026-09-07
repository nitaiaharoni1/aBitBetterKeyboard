import Foundation

extension KeyboardController {
    func insertSpace() {
        Feedback.keyPress()
        retirePendingAutocorrectUndo(.acceptLearning)
        if let query = lastSuggestionQuery, query.autocorrect != store.storedAutocorrectLevel {
            refreshSuggestions(schedulingRefinement: false)
        }
        closeGroupedIfCurrentWord()

        let now = Date()
        if insertsPeriodForDoubleSpace(now: now) { return }
        lastSpaceTapAt = nil
        lastSpacePosition = nil
        commitOrdinarySpace(at: now)
    }

    private func insertsPeriodForDoubleSpace(now: Date) -> Bool {
        guard let last = lastSpaceTapAt,
            now.timeIntervalSince(last) < 0.6,
            selection == nil,
            lastSpacePosition == suggestionPosition,
            contextBefore.hasSuffix(" "),
            !contextBefore.hasSuffix("  ")
        else { return false }
        commitPendingPersonalToken()
        let deleted = deleteBackwardReversibly(utf16Units: 1)
        target?.insertText(deleted.unitsRemoved == 1 ? ". " : " ")
        lastSpaceTapAt = nil
        lastSpacePosition = nil
        armShiftAtBoundary()
        _ = consumeGroupedSkipLearn()
        refreshSuggestions()
        return true
    }

    private func commitOrdinarySpace(at now: Date) {
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
        if autocapitalizationMode == .words { armShiftAtBoundary() }
        refreshSuggestions()
        lastSpaceTapAt = now
        lastSpacePosition = suggestionPosition
    }

    private func automaticSpaceSwap(
        original: String, contextBeforeSwap: String, permitted: Bool
    ) -> (original: String, replacement: String, learnedCommit: LearnedCommit)? {
        guard store.storedAutocorrectLevel != .off,
            !isCorrectingWordByHand,
            selection == nil,
            let after = target?.documentContextAfterInput,
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
