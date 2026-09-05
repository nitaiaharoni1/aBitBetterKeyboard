import XCTest

@testable import AIKeyboardCore

/// Accepting a candidate when a space already follows the caret.
///
/// `apply(_:)` used to write a fresh space whether or not one was already
/// sitting behind the cursor, so `"The teh| quick"` (`|` the caret) committed
/// as `"The the  quick"` — a second space nobody typed. Stock iOS instead
/// replaces the word and hops the caret past the space already doing that
/// job. `MockTextTarget` cannot show any of this: its
/// `documentContextAfterInput` is always empty and its
/// `adjustTextPosition(byCharacterOffset:)` is a no-op, so every case here
/// runs against `CursorTextTarget` and, for the headline case, a real
/// `UITextView` as well.
@MainActor
final class CommittalSpaceHopTests: XCTestCase {

    func testDoubleSpaceOnlyReplacesTheSpaceAtTheSameCaret() {
        let target = CursorTextTarget(before: "hello")
        let controller = KeyboardController(target: target, language: .english)
        controller.insertSpace()
        controller.insertSpace()
        XCTAssertEqual(target.document, "hello. ")
    }

    func testDoubleSpaceDoesNotPunctuateAnotherDocument() {
        let target = CursorTextTarget(before: "hello")
        let controller = KeyboardController(target: target, language: .english)
        controller.insertSpace()
        target.documentIdentifier = UUID()
        controller.insertSpace()
        XCTAssertEqual(target.document, "hello  ")
    }

    func testDoubleSpaceDoesNotPunctuateAfterMovingTheCaretAwayAndBack() {
        let target = CursorTextTarget(before: "hello")
        let controller = KeyboardController(target: target, language: .english)
        controller.insertSpace()
        target.adjustTextPosition(byCharacterOffset: -1)
        controller.refreshSuggestions(schedulingRefinement: false)
        target.adjustTextPosition(byCharacterOffset: 1)
        controller.insertSpace()
        XCTAssertEqual(target.document, "hello  ")
    }

    func testDoubleSpaceDoesNotInsertAPeriodWhenDeletionIsRefused() {
        let target = CursorTextTarget(before: "hello")
        let controller = KeyboardController(target: target, language: .english)
        controller.insertSpace()
        target.backwardDeleteLimit = 0
        controller.insertSpace()
        XCTAssertEqual(target.document, "hello  ")
    }

    func testDoubleSpaceReplacesASelectionWithAnOrdinarySpace() {
        let target = CursorTextTarget(before: "hello")
        let controller = KeyboardController(target: target, language: .english)
        controller.insertSpace()
        let selected = CursorTextTarget(
            before: "hello ", selecting: "world", documentIdentifier: target.documentIdentifier)
        controller.target = selected
        controller.insertSpace()
        XCTAssertEqual(selected.document, "hello  ")
    }

    func testDoubleSpaceWorksWhenTheContextWindowBackfills() {
        let target = CursorTextTarget(before: "earlier hello", window: 9)
        let controller = KeyboardController(target: target, language: .english)
        controller.insertSpace()
        controller.insertSpace()
        XCTAssertEqual(target.document, "earlier hello. ")
    }

    /// Taps `candidate` on `target` and returns the resulting document.
    private func apply(candidate: String, on target: TextTarget) -> String {
        let controller = KeyboardController(target: target, language: .english)
        let suggestion = Suggestion(text: candidate, language: .english, isDefault: true)
        controller.suggestions = [suggestion]
        controller.apply(suggestion)
        switch target {
        case let mock as CursorTextTarget: return mock.document
        case let live as LiveTextViewTarget: return live.document
        default: XCTFail("unhandled TextTarget"); return ""
        }
    }

    /// **The measured bug.** A build that still writes `insertText(" ")`
    /// unconditionally commits `"The the  quick"` — two spaces — which fails
    /// the equality below.
    func testAcceptingACandidateBeforeAnExistingSpaceDoesNotDoubleIt() {
        let target = CursorTextTarget(before: "The teh", after: " quick")
        XCTAssertEqual(apply(candidate: "the", on: target), "The the quick")
        // The caret hopped past the pre-existing space rather than sitting in
        // front of it, so the next keystroke starts a fresh word.
        XCTAssertEqual(
            target.documentContextBeforeInput, "The the ",
            "the caret did not land after the pre-existing space")
    }

    /// The same scenario against a real `UITextView`, so the fix is proven
    /// against UIKit's own text storage and not only against the hand-written
    /// model of it.
    func testAcceptingACandidateBeforeAnExistingSpaceDoesNotDoubleItInARealTextView() {
        let target = LiveTextViewTarget(before: "The teh", after: " quick")
        XCTAssertEqual(apply(candidate: "the", on: target), "The the quick")
        XCTAssertEqual(
            target.documentContextBeforeInput, "The the ",
            "the caret did not land after the pre-existing space")
    }

    /// **Control: nothing follows the caret.** There is no space to hop, so
    /// one is still inserted — this is what stops the fix from becoming "never
    /// insert a space".
    func testAcceptingACandidateAtTheEndOfTheDocumentStillInsertsASpace() {
        let target = CursorTextTarget(before: "The teh")
        XCTAssertEqual(apply(candidate: "the", on: target), "The the ")
    }

    /// **Control: a newline follows the caret, not a space.** Hopping over it
    /// would leave the caret on the next line rather than in the gap this word
    /// is finishing into, so a space is still inserted here too.
    func testANewlineAfterTheCaretIsNotHoppedOver() {
        let target = CursorTextTarget(before: "teh", after: "\nnext")
        XCTAssertEqual(apply(candidate: "the", on: target), "the \nnext")
    }

    /// **Control: a range selection that is not one whole word.** The hop is
    /// scoped to a plain caret; a multi-word or partial selection keeps the
    /// unconditional space `SelectedWordSuggestionTests.testAMultiWordSelectionIsReplacedExactlyAsItStands`
    /// already pins, second space and all — a build that hops here instead
    /// (round one of this fix did) commits a single space and fails the
    /// equality below.
    func testAcceptingACandidateOverAMultiWordSelectionKeepsTheUnconditionalSpace() {
        let target = CursorTextTarget(before: "say ", selecting: "hello world.", after: " now")
        XCTAssertEqual(apply(candidate: "the", on: target), "say the  now")
    }

    func testAcceptingInsideAWordReplacesBothHalvesAndKeepsPunctuation() {
        for (before, after, candidate, expected) in [
            ("The te", "h quick", "the", "The the quick"),
            ("Say (he", "lo), now", "hello", "Say (hello), now"),
            ("hi שָׁ", "לומ next", "שלום", "hi שלום next"),
            ("hi he", "llo", "hello", "hi hello "),
            ("hi he", "llo\nnext", "hello", "hi hello \nnext")
        ] {
            let mock = CursorTextTarget(before: before, after: after)
            let live = LiveTextViewTarget(before: before, after: after)
            XCTAssertEqual(apply(candidate: candidate, on: mock), expected)
            XCTAssertEqual(apply(candidate: candidate, on: live), expected)
        }
    }

    func testAcceptingAtAWordStartInsertsWithoutEatingTheFollowingWord() {
        let target = CursorTextTarget(before: "say ", after: "world")
        XCTAssertEqual(apply(candidate: "hello", on: target), "say hello world")
    }

    func testARefusedMoveOrPartialDeletionLeavesTheWordAndCaretIntact() {
        for limit in [0, 1, 2, 3] {
            let target = CursorTextTarget(before: "The te", after: "h quick")
            target.backwardDeleteLimit = limit
            XCTAssertEqual(
                apply(candidate: "the", on: target), limit == 3 ? "The the quick" : "The teh quick")
            XCTAssertEqual(target.documentContextBeforeInput, limit == 3 ? "The the " : "The te")
        }
        let target = CursorTextTarget(before: "The te", after: "h quick")
        target.refusesForwardMovement = true
        XCTAssertEqual(apply(candidate: "the", on: target), "The teh quick")
        XCTAssertEqual(target.documentContextBeforeInput, "The te")
    }

    func testATapDoesNotInsertOverAPartiallyDeletedPrefixOrRefusedSelection() {
        let prefix = CursorTextTarget(before: "say helo")
        prefix.backwardDeleteLimit = 2
        XCTAssertEqual(apply(candidate: "hello", on: prefix), "say helo")
        let selection = CursorTextTarget(before: "say ", selecting: "helo", after: " now")
        selection.backwardDeleteLimit = 0
        XCTAssertEqual(apply(candidate: "hello", on: selection), "say helo now")
        XCTAssertEqual(selection.selectedText, "helo")
    }

    // MARK: The grouped idle-completion site

    /// **The same defect, at grouped typing's own idle-completion call site**
    /// (the `grouped.isTyping` branch of `performIdleTyping`, in
    /// `KeyboardController+Suggestions.swift`), which wrote `insertText(" ")`
    /// unconditionally exactly as `apply` did. Every grouped idle test in
    /// `GroupedKeysTests` drives `MockTextTarget`, whose after-caret text is
    /// always empty, so none of them could have seen a pre-existing space;
    /// `CursorTextTarget` can.
    func testGroupedIdleCompletionDoesNotDoubleAnExistingSpace() {
        SharedStore.shared.groupedLevel = .l1
        SharedStore.shared.completeOnIdle = true
        SharedStore.shared.spaceOnIdle = true
        defer {
            SharedStore.shared.groupedLevel = .off
            SharedStore.shared.completeOnIdle = false
            SharedStore.shared.spaceOnIdle = false
        }
        let target = CursorTextTarget(before: "", after: " world")
        let controller = KeyboardController(target: target, language: .english)
        controller.shift = .off
        controller.pressGroupedKey("ty\ngh")
        controller.performIdleTyping()

        XCTAssertFalse(controller.grouped.isTyping, "the idle completion never fired")
        // The exact completed word is not asserted, the way the equivalent
        // `GroupedKeysTests.testIdleCompletionSurvivesTheNextGroupedPress`
        // does not either — `UITextChecker`'s answer for a given code is not
        // pinned here. **Only the first assertion rejects a build that still
        // writes an unconditional space**: `"<guess>  world"` still ends in
        // `" world"`, so `hasSuffix` alone cannot see the extra space and is
        // here only to confirm the tail survived untouched, not to reject
        // the regression.
        XCTAssertFalse(target.document.contains("  "), "double space: \(target.document)")
        XCTAssertTrue(target.document.hasSuffix(" world"), target.document)
    }
}
