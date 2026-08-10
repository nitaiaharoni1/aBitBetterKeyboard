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

    /// What the AI actions operate on: the selection if there is one, otherwise
    /// the sentence the cursor sits in.
    public var aiTargetText: String {
        if let selection { return selection }
        return currentSentence
    }

    /// Where one sentence ends and the next begins.
    static let sentenceTerminators = CharacterSet(charactersIn: ".!?\n")

    var currentSentence: String {
        (headBeforeCursor + tailAfterCursor).trimmingCharacters(in: .whitespaces)
    }

    var headBeforeCursor: String {
        let before = contextBefore
        guard
            let range = before.rangeOfCharacter(from: Self.sentenceTerminators, options: .backwards)
        else { return before }
        return String(before[range.upperBound...])
    }

    var tailAfterCursor: String {
        let after = contextAfter
        guard let range = after.rangeOfCharacter(from: Self.sentenceTerminators) else { return after }
        return String(after[..<range.lowerBound])
    }

    var sentenceSpanBeforeCursor: Int {
        let head = headBeforeCursor
        let start = head.firstIndex { !$0.isWhitespace } ?? head.endIndex
        return head[start...].utf16.count
    }

    var sentenceSpanAfterCursor: Int { tailAfterCursor.utf16.count }

    var sentenceDeleteSpanAfterCursor: Int {
        let tail = tailAfterCursor
        guard sentenceSpanBeforeCursor == 0 else { return tail.utf16.count }
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
        target?.insertText(Self.restoringTrailingMarks(of: typed, to: replacement))
    }

    static func restoringTrailingMarks(of typed: String, to replacement: String) -> String {
        let marks = String(typed.reversed().prefix { $0.isPunctuation }.reversed())
        return replacement.hasSuffix(marks) ? replacement : replacement + marks
    }

    func replaceTargetText(with replacement: String) {
        guard !aiSourceText.isEmpty else {
            target?.insertText(replacement)
            return
        }
        if selection != nil {
            target?.deleteBackward()
            target?.insertText(replacement)
            refreshSuggestions()
            return
        }
        let head = sentenceSpanBeforeCursor
        let tail = sentenceSpanAfterCursor
        guard tail > 0 else {
            deleteBackward(utf16Units: head)
            target?.insertText(replacement)
            refreshSuggestions()
            return
        }
        let tailText = tailAfterCursor
        let tailDeletes = sentenceDeleteSpanAfterCursor
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
