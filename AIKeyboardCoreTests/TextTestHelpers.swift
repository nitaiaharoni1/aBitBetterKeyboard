import UIKit
import XCTest

@testable import AIKeyboardCore

/// A document with a cursor and a selection, which `MockTextTarget` does not
/// have.
///
/// `MockTextTarget` is a `String` the keyboard appends to: its
/// `documentContextAfterInput` is always empty and its `selectedText` is always
/// nil, so every text-mutation test written against it exercises exactly one
/// position — caret at the end, nothing selected — and three defects lived in
/// `replaceTargetText` behind that. This models what `UITextDocumentProxy`
/// actually reports: the context *before* a selection, the context after it, and
/// a `deleteBackward()` that consumes the whole selection in one step.
@MainActor
final class CursorTextTarget: TextTarget {
    private var before: String
    private var after: String
    private var selected: String?

    /// How much of the text before the cursor the host is willing to hand over.
    ///
    /// `UITextDocumentProxy` documents `documentContextBeforeInput` as the text
    /// before the cursor, "possibly truncated" — a window, not the document. Nil
    /// means the whole thing, which is what a `UITextView` gives.
    private let window: Int?

    /// The whole document, which is what the assertions are about: the user does
    /// not see three fields, they see one line of text.
    var document: String { before + (selected ?? "") + after }

    init(before: String, selecting: String? = nil, after: String = "", window: Int? = nil) {
        self.before = before
        self.selected = selecting
        self.after = after
        self.window = window
    }

    var documentContextBeforeInput: String? {
        guard let window else { return before }
        return String(before.suffix(window))
    }
    var documentContextAfterInput: String? { after }
    var selectedText: String? { selected }
    var isSecureTextEntry: Bool? { false }
    var textContentType: UITextContentType?? { .some(.none) }
    var keyboardType: UIKeyboardType? { .default }

    func insertText(_ text: String) {
        selected = nil
        before += text
    }

    /// **One press removes the whole selection.** This is the behaviour the old
    /// `for _ in 0..<original.count { deleteBackward() }` loop was blind to.
    func deleteBackward() {
        if selected != nil {
            selected = nil
            return
        }
        if !before.isEmpty { before.removeLast() }
    }

    /// **Counts in UTF-16, because the host does.** Measured on the iPhone 17 Pro
    /// simulator with `offset(from: beginningOfDocument, to: endOfDocument)` on
    /// both `UITextView` and `UITextField`: `abc` is 3, `a😀b` is 4, a flag is 4,
    /// a decomposed `à` is 2, `שָׁ` is 3 and a ZWJ sequence is 5. The first version
    /// of this mock moved in `Character`s, which made it agree with the bug it was
    /// supposed to catch. An offset landing inside a cluster snaps forward, which
    /// is the generous reading of what UIKit does.
    func adjustTextPosition(byCharacterOffset offset: Int) {
        guard offset != 0 else { return }
        if offset > 0 {
            var moved = ""
            for character in after {
                guard moved.utf16.count < offset else { break }
                moved.append(character)
            }
            after.removeFirst(moved.count)
            before += moved
        } else {
            var moved = ""
            for character in before.reversed() {
                guard moved.utf16.count < -offset else { break }
                moved = String(character) + moved
            }
            before.removeLast(moved.count)
            after = moved + after
        }
    }

    /// Puts the caret between `before` and `after` without going through a key.
    /// That is what a tap in the host field does, and `selectionDidChange` is
    /// how the keyboard hears about it.
    func placeCaret(before newBefore: String, after newAfter: String = "") {
        before = newBefore
        after = newAfter
        selected = nil
    }
}

/// The same protocol, over a real `UITextView`.
///
/// `CursorTextTarget` is a model of a document and this is a document: UIKit's
/// own text storage, its own UTF-16 offsets, its own idea of what one backspace
/// removes. The unit mismatch that destroyed the user's text lived in the gap
/// between a hand-written mock and the real thing, so the same cases run against
/// both and the assertions are identical.
@MainActor
final class LiveTextViewTarget: TextTarget {
    let view = UITextView(frame: CGRect(x: 0, y: 0, width: 320, height: 200))

    var document: String { view.text ?? "" }

    init(before: String, selecting: String = "", after: String = "") {
        // Off, so the assertions are about the arithmetic rather than about a
        // straight apostrophe becoming a curly one on the way in.
        view.autocorrectionType = .no
        view.smartQuotesType = .no
        view.smartDashesType = .no
        view.smartInsertDeleteType = .no
        view.text = before + selecting + after
        let start = view.position(from: view.beginningOfDocument, offset: before.utf16.count)!
        let end = view.position(from: start, offset: selecting.utf16.count)!
        view.selectedTextRange = view.textRange(from: start, to: end)
    }

    var documentContextBeforeInput: String? {
        guard let start = view.selectedTextRange?.start,
            let range = view.textRange(from: view.beginningOfDocument, to: start)
        else { return nil }
        return view.text(in: range)
    }

    var documentContextAfterInput: String? {
        guard let end = view.selectedTextRange?.end,
            let range = view.textRange(from: end, to: view.endOfDocument)
        else { return nil }
        return view.text(in: range)
    }

    var selectedText: String? {
        guard let range = view.selectedTextRange, !range.isEmpty else { return nil }
        return view.text(in: range)
    }

    var isSecureTextEntry: Bool? { false }
    var textContentType: UITextContentType?? { .some(.none) }
    /// The view's own trait, not a constant. This wraps a real `UITextView` that
    /// has a real answer, and `TextTarget` forbids reporting a concrete value to
    /// mean "I did not check" — a hardcoded `.default` is exactly that, and it
    /// would leave this helper unable to exercise field shaping at all.
    var keyboardType: UIKeyboardType? { view.keyboardType }

    func insertText(_ text: String) { view.insertText(text) }
    func deleteBackward() { view.deleteBackward() }

    func adjustTextPosition(byCharacterOffset offset: Int) {
        guard let end = view.selectedTextRange?.end,
            let moved = view.position(from: end, offset: offset)
        else { return }
        view.selectedTextRange = view.textRange(from: moved, to: moved)
    }
}
