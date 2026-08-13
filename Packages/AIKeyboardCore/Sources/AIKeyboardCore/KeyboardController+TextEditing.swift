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
    func replaceCurrentWord(with replacement: String) {
        if selection != nil {
            target?.deleteBackward()
            target?.insertText(replacement)
            return
        }
        let typed = currentWordPrefix
        deleteBackward(utf16Units: typed.utf16.count)
        target?.insertText(Self.restoringEdgeMarks(of: typed, to: replacement))
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

    func replaceTargetText(with replacement: String) {
        endGroupedWord()
        guard !aiSourceText.isEmpty else {
            target?.insertText(replacement)
            // **The one branch here that used to skip this, and the only one that
            // changes the document without replacing anything.** It is how a Reply
            // lands — `runReply` empties `aiSourceText` on purpose, because a reply
            // is inserted where the cursor is rather than over the message — and a
            // reply is accepted into an *empty* field more often than not, which is
            // the state Fix and Rewrite are drawn disabled in. Without the refresh
            // their keys stayed dim over a field that now held a whole sentence,
            // until some unrelated keystroke happened to recompute it.
            refreshSuggestions()
            return
        }
        if selection != nil {
            target?.deleteBackward()
            target?.insertText(replacement)
            refreshSuggestions()
            return
        }
        let head = editSpanBeforeCursor
        let tail = editSpanAfterCursor
        guard tail > 0 else {
            deleteBackward(utf16Units: head)
            target?.insertText(replacement)
            refreshSuggestions()
            return
        }
        let tailText = editTail
        let tailDeletes = editDeleteSpanAfterCursor
        target?.adjustTextPosition(byCharacterOffset: tail)
        if contextBefore.hasSuffix(tailText) {
            deleteBackward(utf16Units: head + tailDeletes)
        }
        target?.insertText(replacement)
        refreshSuggestions()
    }

    func deleteBackward(utf16Units count: Int) {
        var remaining = count
        var presses = 0
        while remaining > 0, presses < count + 8 {
            let before = Array(contextBefore.utf16)
            target?.deleteBackward()
            presses += 1
            let removed = Self.unitsRemoved(from: before, to: Array(contextBefore.utf16))
            guard removed > 0 else { return }
            remaining -= removed
        }
    }

    static func unitsRemoved(from before: [UInt16], to after: [UInt16]) -> Int {
        for k in 0...16 where before.count >= k {
            let kept = before.prefix(before.count - k)
            if after.count >= kept.count, after.suffix(kept.count).elementsEqual(kept) { return k }
        }
        return 0
    }
}
