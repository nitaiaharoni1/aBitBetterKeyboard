import Foundation

extension KeyboardController {
    func refreshActiveSuggestions(schedulingRefinement: Bool) {
        guard preparesActiveSuggestionRefresh() else { return }
        let before = contextBefore
        if installsPersonalTokenSuggestions(in: before) { return }

        let typed = currentWordPrefix
        let selected = selectedWord
        let availableAfter = target?.documentContextAfterInput
        if installsTrailingBoundaryRepair(in: before, after: availableAfter) { return }

        let input = suggestionInput(before: before, typed: typed, selected: selected)
        let results = cachedSuggestions(for: input.query)
        publishSuggestionResults(results, prefix: input.prefix)
        scheduleRefinement(
            for: input.prefix, context: input.context,
            enabled: schedulingRefinement && selection == nil)
        dropIdleTypingIfStale()
    }

    private func preparesActiveSuggestionRefresh() -> Bool {
        if isSystemKeyboard, !Self.hasSuggestionMemoryHeadroom(reservingMB: Self.suggestionWorkReserveMB) {
            stopSuggestionWorkForMemoryPressure()
            return false
        }
        expirePendingAutocorrectUndoIfCaretMoved()
        if grouped.isTyping {
            dropIdleTypingIfStale()
            return false
        }
        guard store.storedPredictions,
            SecureField.permitsRead(
                secure: target?.isSecureTextEntry ?? nil, contentType: fieldContentType)
        else {
            refiner?.cancel()
            pendingRefinementPosition = nil
            suggestions = []
            dropIdleTypingIfStale()
            return false
        }
        return true
    }

    private func installsPersonalTokenSuggestions(in before: String) -> Bool {
        guard let personalOffers = personalTokenSuggestions(in: before) else { return false }
        if personalOffers != suggestions { suggestions = personalOffers }
        cancelRefinement()
        dropIdleTypingIfStale()
        return true
    }

    private func installsTrailingBoundaryRepair(in before: String, after availableAfter: String?) -> Bool {
        guard selection == nil,
            let availableAfter,
            !Self.continuesWord(in: availableAfter),
            let repair = MissingSpaces.trailingBoundaryRepair(in: before)
        else { return false }
        let bar = [
            Suggestion(
                text: repair.replacement,
                language: .hebrew,
                commit: .replaceSuffix(expected: repair.source))
        ]
        if bar != suggestions { suggestions = bar }
        cancelRefinement()
        dropIdleTypingIfStale()
        return true
    }

    private func suggestionInput(
        before: String, typed: String, selected: String?
    ) -> (query: SuggestionQuery, prefix: String, context: String) {
        let prefix = selected ?? typed
        let context = String(before.dropLast(typed.count))
        let languages = [language] + store.storedEnabledLanguages.filter { $0 != language }
        let touches: TypingTouchTrace?
        if selection == nil {
            touches = typingTouchTrace.evidence(matching: prefix, context: context)?
                .aligned(to: SuggestionEngine.wordCore(prefix))
        } else {
            typingTouchTrace.clear()
            touches = nil
        }
        let query = SuggestionQuery(
            prefix: prefix,
            context: context,
            languages: languages,
            supplementary: store.storedPersonalDictionary + supplementaryWords,
            autocorrect: store.storedAutocorrectLevel,
            touches: touches,
            vocabulary: vocabularyVersion)
        return (query, prefix, context)
    }

    private func cachedSuggestions(for query: SuggestionQuery) -> [Suggestion] {
        if query == lastSuggestionQuery { return lastSuggestionResults }
        let results = SuggestionEngine.suggestions(
            prefix: query.prefix,
            context: query.context,
            languages: query.languages,
            supplementary: query.supplementary,
            personal: personal,
            autocorrect: query.autocorrect,
            touches: query.touches)
        lastSuggestionQuery = query
        lastSuggestionResults = results
        return results
    }

    private func publishSuggestionResults(_ results: [Suggestion], prefix: String) {
        // Compare before assigning: `@Published` emits on assignment even when
        // the offers did not move, which would rebuild every key and fade the bar.
        let ordinary = results.filter {
            $0.text == prefix || !PersonalLanguageModel.isVerbatimToken($0.text)
        }
        let bar = pinningDefaultToTypedIfNeeded(ordinary, prefix: prefix)
        if bar != suggestions { suggestions = bar }
    }

    private func scheduleRefinement(for prefix: String, context: String, enabled: Bool) {
        if enabled {
            askForRefinement(prefix: prefix, context: context)
        } else if selection != nil {
            // A selection cannot use an async typing answer. Cancel an answer
            // already in flight as well as declining to schedule another one.
            refiner?.cancel()
            pendingRefinementPosition = nil
        }
    }
}
