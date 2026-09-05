import UIKit

extension KeyboardController {

    // MARK: Derived text

    public var contextBefore: String { target?.documentContextBeforeInput ?? "" }
    public var contextAfter: String { target?.documentContextAfterInput ?? "" }
    public var selection: String? {
        guard let text = target?.selectedText, !text.isEmpty else { return nil }
        return text
    }

    /// The partial word under the cursor.
    public var currentWordPrefix: String {
        let before = contextBefore
        guard let last = before.last, !last.isWhitespace else { return "" }
        return String(before.reversed().prefix { !$0.isWhitespace }.reversed())
    }

    /// The word the suggestion bar is scoring: a whole word the host has
    /// selected, otherwise the partial word behind the cursor.
    ///
    /// **Double-tapping a word is how a person asks "what else could this be",
    /// and the bar used to answer about something else entirely.** With a range
    /// selected, `documentContextBeforeInput` stops at the *start* of it, so
    /// `currentWordPrefix` is whatever run of characters sits in front of the
    /// selection — usually nothing at all, which scored the bar as if a new word
    /// were being started in the middle of a sentence.
    public var wordUnderConsideration: String { selectedWord ?? currentWordPrefix }

    static func continuesWord(in contextAfter: String) -> Bool {
        guard let next = contextAfter.first else { return false }
        return next.isLetter || next.isNumber || staysInsideWord(next)
    }

    /// The selection, when it is exactly one whole word and nothing else.
    ///
    /// Three boundary tests, because a selection that is *part* of a word is a
    /// different question and any answer to it would be typed over half a word:
    /// the selection is one token, nothing is joined to its leading end, and
    /// nothing is joined to its trailing end. `wordCore` is what asks the
    /// leading question, not `isEmpty` — an opening bracket or quote in front of
    /// the selection is not a word joined to it, and `("recieve")` is the
    /// ordinary way a misspelling arrives wearing marks it does not own.
    /// `staysInsideWord` asks the trailing one, so selecting `don` out of
    /// `don't` is refused for the same reason typing an apostrophe does not
    /// finish a word.
    ///
    /// A selection that is nothing but punctuation has no core to look up and is
    /// not a word either: `wordCore` answers `""` for it, and `""` is a prefix of
    /// every entry in every list this engine reads — the same trap `comparable`'s
    /// callers already guard.
    var selectedWord: String? {
        guard let selection else { return nil }
        guard !selection.contains(where: { $0.isWhitespace || $0.isNewline }) else { return nil }
        guard !SuggestionEngine.wordCore(selection).isEmpty else { return nil }
        guard SuggestionEngine.wordCore(currentWordPrefix).isEmpty else { return nil }
        guard !Self.continuesWord(in: contextAfter) else { return nil }
        return selection
    }

    /// Trailing whitespace plus the non-whitespace run in front of it.
    ///
    /// **A hold has to take the spaces with the word, or it stalls.** One
    /// character at a time, `"hello "` spends a tick on the space. Punctuation
    /// stays inside the word, matching `currentWordPrefix`, so `"world!"` is
    /// one delete. The caller measures UTF-16, because that is what
    /// `deleteBackward(utf16Units:)` consumes.
    static func previousWordSuffix(in before: String) -> String {
        let reversed = before.reversed()
        let whitespace = reversed.prefix { $0.isWhitespace }
        let word = reversed.drop(while: { $0.isWhitespace }).prefix { !$0.isWhitespace }
        return String(word.reversed()) + String(whitespace.reversed())
    }

    /// What the AI actions operate on: the selection if there is one, otherwise
    /// **everything in the field**.
    ///
    /// **It used to be the sentence the cursor sat in, and that made Fix get worse
    /// the more it was used.** The boundary was `.!?\n`, so a message that had
    /// already been corrected once carried a terminator in the middle of it, and
    /// the second run saw only what came after: type `hi mamiwhat?`, Fix it to
    /// `hi mami what?`, add `up`, and Fix is handed the single word `up` — with no
    /// way to know it belongs to the question in front of it, and no way to produce
    /// `hi mami whats up?`. The same is true of the ordinary case that has nothing
    /// to do with a previous Fix: two sentences typed into one chat message are one
    /// message, and correcting the second while pretending the first is not there
    /// is how a pronoun ends up disagreeing with a name it cannot see.
    ///
    /// So the scope is the field. That is also what these actions are *about* — Fix
    /// and Rewrite are message-level edits, the prompts say `Message:` and hand the
    /// model one, and `OutputGuard` and `EditScope` both judge the answer against
    /// the whole of what was sent. A selection still wins, because a selection is
    /// the user saying which part they mean.
    ///
    /// What the field is, is whatever the host hands over: `documentContextBeforeInput`
    /// and `…AfterInput` are the only readers a keyboard extension has, and iOS
    /// truncates both. There is nothing behind them to reach for, so "everything in
    /// the field" means everything the keyboard can see of it.
    public var aiTargetText: String {
        if let selection { return selection }
        return wholeField
    }

    /// The field, either side of the cursor, with the edges tidied.
    var wholeField: String {
        (editHead + editTail).trimmingCharacters(in: .whitespaces)
    }

    /// The two halves an applied answer replaces. Named for the edit rather than
    /// for the sentence they used to be, because the scope is no longer a sentence
    /// and a name that says otherwise is how the two drift apart.
    var editHead: String { contextBefore }
    var editTail: String { contextAfter }

    /// How much in front of the cursor the replacement covers.
    ///
    /// Leading whitespace is deliberately outside the span: the field may begin
    /// with a space the user put there and an answer is not a claim about it.
    var editSpanBeforeCursor: Int {
        let head = editHead
        let start = head.firstIndex { !$0.isWhitespace } ?? head.endIndex
        return head[start...].utf16.count
    }

    var editSpanAfterCursor: Int { editTail.utf16.count }

    /// The same, behind the cursor — and it skips the tail's leading whitespace
    /// only when there is nothing in front of the cursor at all, which is the one
    /// case where that whitespace is the *start* of the field rather than the gap
    /// between two words the answer spans.
    var editDeleteSpanAfterCursor: Int {
        let tail = editTail
        guard editSpanBeforeCursor == 0 else { return tail.utf16.count }
        let start = tail.firstIndex { !$0.isWhitespace } ?? tail.endIndex
        return tail[start...].utf16.count
    }

    public var hasTextToWorkWith: Bool {
        !aiTargetText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var fieldContentType: UITextContentType?? {
        guard let target else { return UITextContentType??.none }
        return target.textContentType
    }

    // MARK: Text mutation helpers

    /// Swaps the partial word behind the cursor for a candidate.
    @discardableResult
    func replaceCurrentWord(with replacement: String, following suffix: String = "") -> Bool {
        // A replacement is not another physical sample, even when it writes the
        // exact same spelling back. Retaining the old geometry would let a later
        // refresh treat another edit as if the user had just tapped those keys.
        typingTouchTrace.clear()
        guard let target else { return false }
        if selection != nil {
            // One backspace takes the whole selection, and the marks it was
            // wearing go with it: the engine was asked about `wordCore`, so the
            // candidate for a selected `Nitai's` is `Nitai` and inserting it
            // bare deletes the possessive. The same rule the caret path below
            // follows, asked of the selection instead of the keystrokes.
            //
            // **Only for a whole selected word.** "Which marks did this word
            // wear" has no answer for a range spanning two of them: `wordCore`
            // trims the full stop off a selected `hello world.` and the mark
            // would come back glued to a one-word candidate. Read before the
            // delete, which is what clears the selection.
            let word = selectedWord
            target.deleteBackward()
            guard selection == nil else { return false }
            target.insertText(
                word.map { Self.restoringEdgeMarks(of: $0, to: replacement) } ?? replacement)
            return true
        }
        let typed = currentWordPrefix
        let tailUnits = suffix.utf16.count
        if !suffix.isEmpty {
            let before = contextBefore
            guard let after = target.documentContextAfterInput, after.hasPrefix(suffix) else {
                return false
            }
            target.adjustTextPosition(byCharacterOffset: tailUnits)
            let moved = Self.forwardMovement(
                from: before, through: after, to: contextBefore, remaining: contextAfter)
            guard moved == tailUnits else {
                if moved > 0 { target.adjustTextPosition(byCharacterOffset: -moved) }
                return false
            }
        }
        let word = typed + suffix
        let deletion = deleteBackwardReversibly(utf16Units: word.utf16.count)
        guard deletion.unitsRemoved == word.utf16.count else {
            if !deletion.deletedText.isEmpty { target.insertText(deletion.deletedText) }
            if tailUnits > 0 { target.adjustTextPosition(byCharacterOffset: -tailUnits) }
            return false
        }
        target.insertText(Self.restoringEdgeMarks(of: word, to: replacement))
        return true
    }

    /// A candidate wearing the marks the typed word wore.
    ///
    /// **`replaceCurrentWord` deletes the whole prefix, and the whole prefix
    /// includes the punctuation**, so without this every correction ate a mark:
    /// `recieve,` committed as `receive `, `helo,` as `help `.
    ///
    /// **Both edges, because `SuggestionEngine` now reads both.** This restored
    /// the trailing run alone, which was enough while a leading mark stopped every
    /// lookup dead — `(recieve` reached `receive` through `UITextChecker.guesses`
    /// and quietly dropped the bracket, and nothing else got that far. The engine
    /// asks its sources about `wordCore` now, so an opening bracket or quote no
    /// longer hides the word inside it, and the mark has to come home the same way
    /// the closing one does.
    ///
    /// **It restores exactly what `wordCore` removed, rather than re-deriving it.**
    /// A version of this that put back the punctuation *runs* at each end looked
    /// equivalent and was not, because `wordCore` also strips a possessive `'s` —
    /// and `'s` is not a run of punctuation, it ends in a letter. So the engine
    /// reduced `Nitai's` to `Nitai`, offered a correction of that, and the
    /// possessive was deleted: `Nitai's` committed as `Nit`. Locating the core
    /// inside the keystrokes makes the two halves impossible to drift apart, which
    /// matters because they live in different files.
    ///
    /// Neither side is added when the candidate already carries it, because
    /// candidate zero *is* the literal keystrokes and would otherwise double them.
    /// A prefix that is nothing but punctuation has no core, and nothing to
    /// restore around: it is returned as it came.
    static func restoringEdgeMarks(of typed: String, to replacement: String) -> String {
        let core = SuggestionEngine.wordCore(typed)
        guard !core.isEmpty, let range = typed.range(of: core, options: .literal) else {
            return replacement
        }
        let leading = String(typed[..<range.lowerBound])
        let trailing = String(typed[range.upperBound...])
        var out = replacement
        if !out.hasPrefix(leading) { out = leading + out }
        if !out.hasSuffix(trailing) { out += trailing }
        return out
    }

    /// Replaces the requested span only when every destructive step completed.
    /// A partial delete is put back byte for byte and reports failure.
    @discardableResult
    func replaceTargetText(with replacement: String) -> Bool {
        typingTouchTrace.clear()
        endGroupedWord()
        guard let target else {
            refreshSuggestions()
            return false
        }
        guard !aiSourceText.isEmpty else {
            target.insertText(replacement)
            // **The one branch here that used to skip this, and the only one that
            // changes the document without replacing anything.** It is how a Reply
            // lands — `runReply` empties `aiSourceText` on purpose, because a reply
            // is inserted where the cursor is rather than over the message — and a
            // reply is accepted into an *empty* field more often than not, which is
            // the state Fix and Rewrite are drawn disabled in. Without the refresh
            // their keys stayed dim over a field that now held a whole sentence,
            // until some unrelated keystroke happened to recompute it.
            refreshSuggestions()
            return true
        }
        if selection != nil {
            target.deleteBackward()
            target.insertText(replacement)
            refreshSuggestions()
            return true
        }
        let head = editSpanBeforeCursor
        let tail = editSpanAfterCursor
        guard tail > 0 else {
            let deletion = deleteBackwardReversibly(utf16Units: head)
            guard deletion.unitsRemoved == head else {
                if !deletion.deletedText.isEmpty { target.insertText(deletion.deletedText) }
                refreshSuggestions()
                return false
            }
            target.insertText(replacement)
            refreshSuggestions()
            return true
        }
        let contextBeforeMove = contextBefore
        let contextAfterMove = contextAfter
        let tailDeletes = editDeleteSpanAfterCursor
        target.adjustTextPosition(byCharacterOffset: tail)
        // **The insert used to happen whether or not the delete did, and that
        // duplicated the message.** If the caret did not land where this expects,
        // the delete was skipped and the replacement went in anyway, so the field
        // ended up holding the original text *and* the whole answer. The guard is
        // this code saying it has lost track of the field; inserting on a model
        // known to be wrong is the one response guaranteed to make it worse.
        //
        // It fails for two reasons that are not bugs: `adjustTextPosition` is a
        // request the host may not honour, and `documentContextBeforeInput` is
        // truncated by iOS, so a `tailText` longer than the window cannot be
        // matched at all. Neither is a reason to write.
        //
        // Pre-existing, and reachable far more often since the undo stopped
        // expiring at the next keystroke: `revertEdit`'s `.wholeField` branch
        // comes through here with the caret wherever the user left it, which was
        // a state the old one-keystroke lifetime made nearly unreachable.
        let moved = Self.forwardMovement(
            from: contextBeforeMove,
            through: contextAfterMove,
            to: contextBefore,
            remaining: contextAfter)
        guard moved == tail else {
            if moved > 0 { target.adjustTextPosition(byCharacterOffset: -moved) }
            refreshSuggestions()
            return false
        }
        let requestedUnits = head + tailDeletes
        let deletion = deleteBackwardReversibly(utf16Units: requestedUnits)
        guard deletion.unitsRemoved == requestedUnits else {
            if !deletion.deletedText.isEmpty { target.insertText(deletion.deletedText) }
            target.adjustTextPosition(byCharacterOffset: -tail)
            refreshSuggestions()
            return false
        }
        target.insertText(replacement)
        refreshSuggestions()
        return true
    }

    /// What a backward-delete loop actually removed. `deletedText` is assembled
    /// in document order so a refused or partial edit can put it straight back.
    struct BackwardDeletion {
        var unitsRemoved = 0
        var deletedText = ""
    }

    @discardableResult
    func deleteBackward(utf16Units count: Int) -> Int {
        deleteBackwardReversibly(utf16Units: count).unitsRemoved
    }

    func deleteBackwardReversibly(utf16Units count: Int) -> BackwardDeletion {
        var result = BackwardDeletion()
        guard let target else { return result }
        while result.unitsRemoved < count {
            guard let beforeText = target.documentContextBeforeInput else { return result }
            let before = Array(beforeText.utf16)
            guard let trailingCharacter = beforeText.last else { return result }
            target.deleteBackward()
            guard let afterText = target.documentContextBeforeInput else { return result }
            let removed = Self.unitsRemoved(
                from: before,
                to: Array(afterText.utf16),
                expectedTrailingCharacterWidth: String(trailingCharacter).utf16.count)
            guard removed > 0 else { return result }
            let deleted = String(decoding: before.suffix(removed), as: UTF16.self)
            result.unitsRemoved += removed
            result.deletedText = deleted + result.deletedText
        }
        return result
    }

    static func unitsRemoved(
        from before: [UInt16],
        to after: [UInt16],
        expectedTrailingCharacterWidth: Int
    ) -> Int {
        var candidates = Array(0...min(16, before.count))
        if expectedTrailingCharacterWidth > 16,
            expectedTrailingCharacterWidth <= before.count
        {
            candidates.append(expectedTrailingCharacterWidth)
        }
        for k in candidates {
            let kept = before.prefix(before.count - k)
            if after.count >= kept.count, after.suffix(kept.count).elementsEqual(kept) { return k }
        }
        return 0
    }

    /// How far a host moved through a tail when it honoured only part of a caret
    /// request. The exact unchanged snapshot wins first so repeated text cannot
    /// turn a refusal into a backwards move into the user's message.
    static func forwardMovement(
        from originalBefore: String,
        through originalAfter: String,
        to currentBefore: String,
        remaining currentAfter: String
    ) -> Int {
        guard currentBefore != originalBefore || currentAfter != originalAfter else { return 0 }
        var moved = ""
        var index = originalAfter.startIndex
        var best = 0
        while index < originalAfter.endIndex {
            let next = originalAfter.index(after: index)
            moved += originalAfter[index..<next]
            let remaining = originalAfter[next...]
            if currentBefore.hasSuffix(moved), currentAfter.hasPrefix(remaining) {
                best = moved.utf16.count
            }
            index = next
        }
        return best
    }
}
