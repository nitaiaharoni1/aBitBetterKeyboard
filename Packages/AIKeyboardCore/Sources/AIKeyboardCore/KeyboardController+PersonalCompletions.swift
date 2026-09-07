import Foundation

extension KeyboardController {
    func preparePersonalTokenForInput(_ input: String) -> Bool {
        guard let draft = pendingPersonalValue else { return input == "@" }
        if contextBefore.last?.isWhitespace != true {
            if draft.kind == .phone, input.first == "." { return true }
            if draft.kind == .phone, PersonalToken.accepts(input, kind: .email),
                !PersonalToken.accepts(input, kind: .phone)
            {
                pendingPersonalValue = nil
                return true
            }
            if draft.kind == .email, input.contains("/") || input.contains("\\") {
                pendingPersonalValue = nil
                return true
            }
        }
        if PersonalToken.accepts(input, kind: draft.kind) { return true }
        if draft.kind == .phone, contextBefore.last?.isWhitespace != true,
            !Self.finishesWord(input)
        {
            pendingPersonalValue = nil
        } else {
            commitPendingPersonalToken()
        }
        return true
    }

    @discardableResult
    func stagePersonalToken() -> Bool {
        let before = contextBefore
        let documentIdentifier = target?.documentIdentifier
        if let pendingPersonalValue, pendingPersonalValue.documentIdentifier != documentIdentifier {
            commitPendingPersonalToken()
        }
        guard selection == nil else {
            pendingPersonalValue = nil
            return false
        }
        let candidate: (text: String, kind: PersonalToken.Kind)?
        if let email = PersonalToken.prefix(in: before, kind: .email), email.contains("@") {
            candidate = (email, .email)
        } else if let phone = PersonalToken.prefix(in: before, kind: .phone),
            let digits = PersonalToken.key(for: phone, kind: .phone),
            digits.filter(\.isNumber).count >= 3
        {
            candidate = (phone, .phone)
        } else {
            candidate = nil
        }
        guard let candidate,
            let after = target?.documentContextAfterInput,
            !PersonalToken.continues(in: after, kind: candidate.kind)
        else {
            if before.isEmpty, !documentHasText, deletedWordPrefix == nil {
                commitPendingPersonalToken()
            } else if let draft = pendingPersonalValue, draft.kind == .phone,
                before.hasPrefix(draft.contextBefore),
                before.count > draft.contextBefore.count,
                before.dropFirst(draft.contextBefore.count).allSatisfy({ $0 == "." || $0.isWhitespace }),
                let after = target?.documentContextAfterInput,
                !PersonalToken.continues(in: after, kind: .phone)
            {
                if before.dropFirst(draft.contextBefore.count).contains(where: \.isWhitespace) {
                    commitPendingPersonalToken()
                } else {
                    return true
                }
            } else if let draft = pendingPersonalValue, draft.kind == .email,
                before.hasPrefix(draft.contextBefore),
                before.dropFirst(draft.contextBefore.count).first?.isWhitespace == true
            {
                commitPendingPersonalToken()
            } else {
                pendingPersonalValue = nil
            }
            return false
        }
        pendingPersonalValue = PendingPersonalToken(
            kind: candidate.kind, text: candidate.text, contextBefore: before,
            documentIdentifier: documentIdentifier,
            language: language,
            permitted: SecureField.permitsRead(
                secure: target?.isSecureTextEntry ?? nil, contentType: fieldContentType))
        return true
    }

    public func commitPendingPersonalToken() {
        guard let draft = pendingPersonalValue else { return }
        pendingPersonalValue = nil
        let before = contextBefore
        if draft.documentIdentifier == target?.documentIdentifier,
            !before.isEmpty, !before.hasPrefix(draft.contextBefore)
        {
            return
        }
        let text = PersonalToken.completedText(draft.text, kind: draft.kind)
        if personal.recordVerbatimToken(text, language: draft.language, permitted: draft.permitted) {
            vocabularyVersion &+= 1
        }
        openWord = ""
    }

    func personalTokenSuggestions(in before: String) -> [Suggestion]? {
        guard selection == nil, before.last?.isWhitespace == false,
            let after = target?.documentContextAfterInput,
            SecureField.permitsRead(
                secure: target?.isSecureTextEntry ?? nil, contentType: fieldContentType)
        else { return nil }
        var matches: [(prefix: String, values: [String])] = []
        for kind in [PersonalToken.Kind.email, .phone] {
            guard let prefix = PersonalToken.prefix(in: before, kind: kind),
                !PersonalToken.continues(in: after, kind: kind)
            else { continue }
            let values = personalTokenMatches(prefix: prefix, kind: kind)
            guard !values.isEmpty else { continue }
            matches.append((prefix, values))
        }
        guard let prefix = matches.max(by: { $0.prefix.count < $1.prefix.count })?.prefix else { return nil }
        let values = matches.filter { $0.prefix == prefix }.flatMap(\.values)
            .sorted {
                let lhs = personal.count(of: $0, in: language)
                let rhs = personal.count(of: $1, in: language)
                return lhs == rhs ? $0 < $1 : lhs > rhs
            }.prefix(SuggestionEngine.barSlots)
        return [
            Suggestion(
                text: prefix, language: language, isDefault: true,
                commit: .verbatimToken(expected: prefix))
        ]
            + values.map {
                Suggestion(text: $0, language: language, commit: .verbatimToken(expected: prefix))
            }
    }

    private func personalTokenMatches(prefix: String, kind: PersonalToken.Kind) -> [String] {
        guard let key = PersonalToken.completionKey(for: prefix, kind: kind) else { return [] }
        personal.reload()
        let manual = (store.storedPersonalDictionary + supplementaryWords).filter {
            guard PersonalToken.kind(of: $0) == kind,
                let candidate = PersonalToken.key(for: $0, kind: kind)
            else { return false }
            return candidate != key && candidate.hasPrefix(key)
        }
        let learned = personal.verbatimTokens(
            startingWith: prefix, kind: kind, limit: SuggestionEngine.barSlots)
        var seen = Set<String>()
        return Array(
            (manual + learned).filter {
                guard let key = PersonalToken.key(for: $0, kind: kind) else { return false }
                return seen.insert(key).inserted
            }.prefix(SuggestionEngine.barSlots))
    }

    func applyPersonalToken(_ suggestion: Suggestion) -> Bool {
        let kind = PersonalToken.kind(of: suggestion.text)
        let expected: String
        if case .verbatimToken(let prefix) = suggestion.commit {
            expected = prefix
        } else if let kind, let prefix = PersonalToken.prefix(in: contextBefore, kind: kind) {
            expected = prefix
        } else {
            return kind != nil
        }
        personal.reload()
        guard let kind, selection == nil,
            contextBefore.hasSuffix(expected),
            PersonalToken.prefix(in: contextBefore, kind: kind) == expected,
            let after = target?.documentContextAfterInput,
            !PersonalToken.continues(in: after, kind: kind),
            SecureField.permitsRead(
                secure: target?.isSecureTextEntry ?? nil, contentType: fieldContentType),
            personalTokenMatches(prefix: expected, kind: kind).contains(suggestion.text)
        else {
            refreshSuggestions()
            return true
        }
        Feedback.keyPress()
        Feedback.keyClick(.tock)
        let deletion = deleteBackwardReversibly(utf16Units: expected.utf16.count)
        guard deletion.unitsRemoved == expected.utf16.count else {
            if !deletion.deletedText.isEmpty { target?.insertText(deletion.deletedText) }
            refreshSuggestions()
            return true
        }
        retirePendingAutocorrectUndo(.acceptLearning)
        endGroupedWord()
        clearRevertibleEdit()
        pendingPersonalValue = nil
        target?.insertText(suggestion.text)
        personal.recordVerbatimToken(
            suggestion.text, language: suggestion.language, permitted: true, source: .selectedSuggestion)
        vocabularyVersion &+= 1
        if after.isEmpty || after.first == " " { insertCommittalSpace(after: after) }
        deletedWordPrefix = nil
        openWord = ""
        lastLearnedFolded = nil
        cancelRefinement()
        refreshSuggestions()
        reportInteraction(.suggestion)
        return true
    }
}
