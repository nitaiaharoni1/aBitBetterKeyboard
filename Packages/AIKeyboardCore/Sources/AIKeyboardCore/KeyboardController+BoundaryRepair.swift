extension KeyboardController {

    /// A boundary repair is valid only for the exact document suffix that
    /// produced it. Recompute the lexicon decision here before deleting anything.
    func applyBoundaryRepair(_ suggestion: Suggestion) -> Bool {
        guard case .replaceSuffix(let expected) = suggestion.commit else { return false }
        Feedback.keyPress()

        let before = contextBefore
        guard let after = target?.documentContextAfterInput else {
            refreshSuggestions()
            return true
        }
        guard
            selection == nil,
            before.hasSuffix(expected),
            !Self.continuesWord(in: after),
            let repair = MissingSpaces.trailingBoundaryRepair(in: before),
            repair.source == expected,
            repair.replacement == suggestion.text
        else {
            refreshSuggestions()
            return true
        }

        Feedback.keyClick(.tock)
        let requestedUnits = repair.source.utf16.count
        let deletedUnits = deleteBackward(utf16Units: requestedUnits)
        guard deletedUnits == requestedUnits else {
            // Boundary repairs contain only Hebrew letters and U+0020, so every
            // deleted UTF-16 unit is exactly one trailing Character.
            target?.insertText(String(repair.source.suffix(deletedUnits)))
            refreshSuggestions()
            return true
        }
        retirePendingAutocorrectUndo(.acceptLearning)
        endGroupedWord()
        clearRevertibleEdit()
        target?.insertText(repair.replacement)
        refreshSuggestions()
        revertibleEdit = RevertibleEdit(
            origin: .spacing,
            previous: repair.source,
            applied: repair.replacement,
            undo: .spanAtCursor)
        reportInteraction(.suggestion)
        return true
    }
}
