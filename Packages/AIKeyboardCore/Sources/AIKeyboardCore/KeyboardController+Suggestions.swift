extension KeyboardController {

    // MARK: Suggestions

    public func refreshSuggestions() {
        guard store.predictions else {
            suggestions = []
            return
        }
        let prefix = currentWordPrefix
        let before = contextBefore
        let context = prefix.isEmpty ? before : String(before.dropLast(prefix.count))
        suggestions = SuggestionEngine.suggestions(
            prefix: prefix,
            context: context,
            languages: [language] + store.enabledLanguages.filter { $0 != language },
            supplementary: store.storedPersonalDictionary + supplementaryWords
        )
    }

    public func updateSupplementaryLexicon(_ words: [String]) {
        supplementaryWords = words
        refreshSuggestions()
    }

    public func apply(_ suggestion: Suggestion) {
        Feedback.keyPress()
        replaceCurrentWord(with: suggestion.text)
        target?.insertText(" ")
        refreshSuggestions()
    }
}
