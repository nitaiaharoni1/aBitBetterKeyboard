import UIKit
import XCTest

@testable import AIKeyboardCore

/// `openWord` is the safety net that lets a chat Send teach the last word of a
/// message even though Send never presses space. Two ways it used to learn the
/// wrong thing: a caret merely repositioned inside or beside a word, and a word
/// typed under one field's permission committed under a different field's.
@MainActor
final class OpenWordLifecycleTests: XCTestCase {

    private var autocorrectLevel = AutocorrectLevel.full

    override func setUp() {
        super.setUp()
        autocorrectLevel = SharedStore.shared.autocorrectLevel
        SharedStore.shared.autocorrectLevel = .full
    }

    override func tearDown() {
        SharedStore.shared.autocorrectLevel = autocorrectLevel
        super.tearDown()
    }

    // MARK: A caret parked mid-word

    /// **The measured defect.** `adoptOpenWord` adopted `currentWordPrefix` on
    /// every refresh with no check that the word continues past the caret, so
    /// tapping into the middle of an already-finished word restaged the
    /// fragment in front of the caret as the word to learn.
    func testCaretParkedMidWordThenMovedLearnsNothingOfTheFragment() {
        let target = CursorTextTarget(before: "world", after: "")
        let controller = KeyboardController(target: target, language: .english)
        controller.refreshSuggestions()

        // Tap into the middle: "wor|ld".
        target.placeCaret(before: "wor", after: "ld")
        controller.refreshSuggestions()

        // The host then empties the field, the way a chat Send does.
        target.placeCaret(before: "", after: "")
        controller.refreshSuggestions()

        XCTAssertEqual(
            controller.personal.count(of: "wor", in: .english), 0,
            "a caret parked mid-word must never be learned as its own word")
        XCTAssertEqual(
            controller.personal.count(of: "world", in: .english), 1,
            "the word actually finished being typed is what Send should still teach")
    }

    // MARK: A caret tapped to a word boundary

    /// **The other half of the same defect.** The commit trigger was
    /// `currentWordPrefix.isEmpty`, which is true of any caret sitting at a
    /// word boundary — not only of the document actually being empty — so
    /// tapping between two words in the middle of an unfinished message
    /// committed whatever `openWord` still held.
    func testCaretTappedToABoundaryInANonEmptyDocumentLearnsNothing() {
        let target = CursorTextTarget(before: "hello world", after: "")
        let controller = KeyboardController(target: target, language: .english)
        controller.refreshSuggestions()

        // Tap to the boundary between the two words: "hello |world".
        target.placeCaret(before: "hello ", after: "world")
        controller.refreshSuggestions()

        XCTAssertEqual(
            controller.personal.count(of: "world", in: .english), 0,
            "a caret tapped to a word boundary in a non-empty document must not "
                + "commit the word it left")
    }

    // MARK: The control: Send still teaches the last word

    /// The behaviour the two tests above must not cost: a host that genuinely
    /// empties the field still teaches the word that was left open in it.
    func testHostClearingTheFieldStillLearnsTheLastOpenWord() {
        let target = CursorTextTarget(before: "world", after: "")
        let controller = KeyboardController(target: target, language: .english)
        controller.refreshSuggestions()

        target.placeCaret(before: "", after: "")
        controller.refreshSuggestions()

        XCTAssertEqual(
            controller.personal.count(of: "world", in: .english), 1,
            "chat Send must still teach the last open word")
    }

    // MARK: learnWordJustCommitted's own fragment guard

    /// `learnWordJustCommitted` writes straight to the personal dictionary
    /// rather than staging in `openWord`, so the same fragment leak is worse
    /// here: a terminator (space, Return, a mark) pressed with the caret
    /// mid-word reached this function with `currentWordPrefix` already cut at
    /// the caret.
    func testLearnWordJustCommittedRefusesAFragmentBehindAMidWordCaret() {
        let target = CursorTextTarget(before: "hel", after: "lo")
        let controller = KeyboardController(target: target, language: .english)

        controller.learnWordJustCommitted()

        XCTAssertEqual(
            controller.personal.count(of: "hel", in: .english), 0,
            "a caret sitting mid-word must not teach the fragment behind it")
    }

    // MARK: A refused credential field must not leak into the next document

    /// **Confirmed separately from the caret defects above.** A word left open
    /// in a credential field survives in `openWord` until something commits it,
    /// and this controller's `target` is reused across fields and across host
    /// apps — so by the time a later, permitting field triggers the commit
    /// path, re-deriving permission from `target` judges the word by a field it
    /// was never typed into.
    func testAWordAdoptedUnderARefusingFieldIsNotLearnedUnderTheNextFieldsPermission() {
        let refusing = MutableSecureTarget(before: "secretword", secure: false, contentType: .password)
        let controller = KeyboardController(target: refusing, language: .english)
        controller.refreshSuggestions()

        let permitting = MutableSecureTarget(before: "", secure: false, contentType: nil)
        controller.attach(target: permitting)
        controller.prepareForNewDocument()
        controller.refreshSuggestions()

        XCTAssertEqual(
            controller.personal.count(of: "secretword", in: .english), 0,
            "a word typed under a refusing field must not be learned once a "
                + "permitting field takes over")
    }

    /// **The control.** The same dance under two permitting fields still
    /// teaches the word — the fix is capturing *which* field's permission
    /// applies, not discarding every word that outlives a field switch.
    func testAWordAdoptedUnderAPermittingFieldIsStillLearnedAfterSwitchingFields() {
        let first = MutableSecureTarget(before: "ordinaryword", secure: false, contentType: nil)
        let controller = KeyboardController(target: first, language: .english)
        controller.refreshSuggestions()

        let second = MutableSecureTarget(before: "", secure: false, contentType: nil)
        controller.attach(target: second)
        controller.prepareForNewDocument()
        controller.refreshSuggestions()

        XCTAssertEqual(
            controller.personal.count(of: "ordinaryword", in: .english), 1,
            "a word typed under a permitting field must still be learned after "
                + "switching to another permitting field")
    }
}

/// A `TextTarget` whose secure-entry answer and content type are set by the
/// test, which none of the existing fixtures allow: `MockTextTarget` and
/// `CursorTextTarget` both answer a fixed, permitting pair.
@MainActor
private final class MutableSecureTarget: TextTarget {
    var before: String
    var after: String = ""
    let secure: Bool?
    let contentType: UITextContentType?

    init(before: String, secure: Bool?, contentType: UITextContentType?) {
        self.before = before
        self.secure = secure
        self.contentType = contentType
    }

    var documentContextBeforeInput: String? { before }
    var documentContextAfterInput: String? { after }
    var selectedText: String? { nil }
    var isSecureTextEntry: Bool? { secure }
    var textContentType: UITextContentType?? { .some(contentType) }
    var keyboardType: UIKeyboardType? { .default }

    func insertText(_ text: String) { before += text }
    func deleteBackward() { if !before.isEmpty { before.removeLast() } }
    func adjustTextPosition(byCharacterOffset offset: Int) {}
}
