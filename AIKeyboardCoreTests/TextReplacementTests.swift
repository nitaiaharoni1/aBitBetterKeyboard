import UIKit
import XCTest

@testable import AIKeyboardCore

/// Where the answer from an AI action lands in the document.
///
/// D6 puts Rewrite one tap away in the suggestion row, which is what makes these
/// reachable: before it, every one of them needed the user to open a panel first.
///
/// **The span is the whole field now, and it used to be the sentence.** Every
/// expectation below that names a sentence was rewritten when
/// `KeyboardController.aiTargetText` widened — see its doc comment for the defect,
/// which is `testAnEarlierSentenceIsPartOfTheSpan`. What these tests are actually
/// about did not change and is the reason they were kept rather than replaced: the
/// arithmetic that steps over a tail and deletes backwards has to count UTF-16
/// units the way the host does, and an emoji, a flag, a ZWJ sequence, a decomposed
/// accent and Hebrew niqqud each break a different wrong way of counting.
@MainActor
final class TextReplacementTests: XCTestCase {

    /// The first move every AI action makes, so these tests replace text the same
    /// way `run(_:)` and `runDefaultTone()` do.
    private func apply(_ replacement: String, to controller: KeyboardController) {
        controller.aiSourceText = controller.aiTargetText
        controller.applyResult(replacement)
    }

    /// One case, run twice: against a model of a document and against a real
    /// `UITextView`. The unit bug this exists for was invisible to the model
    /// alone, because the model had been written with the same wrong assumption.
    private func check(
        before: String,
        after: String = "",
        replacement: String,
        field: String? = nil,
        expected: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let mock = CursorTextTarget(before: before, after: after)
        let mockController = KeyboardController(target: mock)
        if let field {
            XCTAssertEqual(mockController.aiTargetText, field, file: file, line: line)
        }
        apply(replacement, to: mockController)
        XCTAssertEqual(mock.document, expected, "against the model", file: file, line: line)

        let live = LiveTextViewTarget(before: before, after: after)
        let liveController = KeyboardController(target: live)
        if let field {
            XCTAssertEqual(liveController.aiTargetText, field, file: file, line: line)
        }
        apply(replacement, to: liveController)
        XCTAssertEqual(live.document, expected, "against a real UITextView", file: file, line: line)
    }

    // MARK: A character is not a character

    /// **An emoji in front of the caret used to eat the text before it.** The step
    /// over the tail counted grapheme clusters and the host counts UTF-16, so the
    /// cursor stopped one unit short of the end while the backspace loop ran the
    /// full length: the field came back as `Hi.Replacementx`.
    func testAnEmojiInTheTailDoesNotEatTheTextBeforeIt() {
        check(
            before: "Hi. hey ", after: "😊 six", replacement: "Replacement",
            field: "Hi. hey 😊 six", expected: "Replacement")
    }

    /// A flag is one grapheme and four UTF-16 units — the widest gap of the lot.
    func testAFlagInTheTail() {
        check(
            before: "Hi. from ", after: "🇮🇱 today", replacement: "From Israel today.",
            field: "Hi. from 🇮🇱 today", expected: "From Israel today.")
    }

    /// A ZWJ sequence is one grapheme and five UTF-16 units.
    func testAZeroWidthJoinerSequenceInTheTail() {
        check(
            before: "Hi. ask ", after: "👩‍💻 later", replacement: "I'll ask her later.",
            field: "Hi. ask 👩‍💻 later", expected: "I'll ask her later.")
    }

    /// **A decomposed accent, which is the one that reaches ordinary users.**
    /// French, Spanish and Portuguese are three of the fourteen layouts, and text
    /// pasted from the web or typed on a Mac arrives in NFD often enough: `à` as
    /// `a` + U+0300 is one grapheme and two UTF-16 units. The broken build strands
    /// a character off the end of the answer.
    func testADecomposedAccentInTheTail() {
        check(
            before: "Bonjour. on se ", after: "voit a\u{0300} six",
            replacement: "On se voit à 18h",
            field: "Bonjour. on se voit a\u{0300} six", expected: "On se voit à 18h")
    }

    /// **Hebrew niqqud and an emoji in the same deleted span, because either one
    /// alone lets a wrong loop through.** `שָׁ` is one grapheme, three UTF-16 units
    /// and three presses, so a loop counting presses in UTF-16 gets it right by
    /// accident; 🎉 is one grapheme, two units and one press, so a loop counting
    /// presses in clusters gets *that* one right by accident. Only a span holding
    /// both rejects both, and the fix is a loop that counts neither and measures
    /// instead.
    func testHebrewNiqqudAndAnEmojiInOneDeletedSpan() {
        check(
            before: "הי. נדבר ", after: "בשָׁעה 🎉 שתים", replacement: "נדבר בשתיים",
            field: "הי. נדבר בשָׁעה 🎉 שתים", expected: "נדבר בשתיים")
    }

    // MARK: The gap in front of the field

    /// **A cursor at the very start, with the field's first real character behind
    /// it.** The head is empty, so leading whitespace is the only thing that can
    /// tell "the start of the field" from "the gap before the first word" — and it
    /// belongs to the user, not to the answer. `editDeleteSpanAfterCursor`'s
    /// `editSpanBeforeCursor == 0` branch is the whole of this case, and the
    /// widened scope left it as the only way in.
    func testWhitespaceInFrontOfTheFieldIsNotPartOfTheSpan() {
        check(
            before: "", after: "  see you at six", replacement: "See you at 6.",
            field: "see you at six", expected: "  See you at 6.")
    }

    /// A cursor sitting immediately after a full stop, which used to make that stop
    /// the boundary of the edit and now does not: the sentence in front of the
    /// cursor is part of the same message and is replaced with it.
    func testTextBeforeAnEarlierFullStopIsReplacedToo() {
        check(
            before: "Hi.", after: " see you at six", replacement: "Hi, see you at 6.",
            field: "Hi. see you at six", expected: "Hi, see you at 6.")
    }

    func testTheWholeFieldIsReplacedInHebrewToo() {
        check(
            before: "היי.", after: " נדבר בשש", replacement: "היי, נדבר בשש",
            field: "היי. נדבר בשש", expected: "היי, נדבר בשש")
    }

    // MARK: A windowed context

    /// **`documentContextBeforeInput` is documented as "possibly truncated", and
    /// the loop used to read the truncation as "nothing was deleted".** With a
    /// full window, one backspace lets a character in at the left as one leaves at
    /// the right, so the length comes back unchanged; the length comparison read
    /// that as zero, stopped after a single press, and left
    /// `Hi. see you at six tomorroRunning late.` — one cluster of the user's text
    /// destroyed and the rest of the sentence still there.
    ///
    /// What the window does *not* do is change the contract: the keyboard replaces
    /// the field it can see, exactly, and nothing outside it. The expectation is
    /// built from `aiTargetText` rather than typed out, because the visible field
    /// is shorter than the real one here — that is the honest consequence of a host
    /// that hands over a window, and the assertion would otherwise be asserting the
    /// window size rather than the behaviour. It is also the answer to "why not
    /// just read the whole document": there is no API that does.
    private func checkWindowed(
        document: String, window: Int, replacement: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let target = CursorTextTarget(before: document, window: window)
        let controller = KeyboardController(target: target)

        let visible = controller.aiTargetText
        XCTAssertFalse(visible.isEmpty, file: file, line: line)
        XCTAssertTrue(
            document.hasSuffix(visible), "the visible field has to be the end of the document",
            file: file, line: line)
        apply(replacement, to: controller)

        XCTAssertEqual(
            target.document, String(document.dropLast(visible.count)) + replacement,
            "the loop deleted something other than exactly the text it could see",
            file: file, line: line)
    }

    func testAWindowedContextDeletesExactlyTheTextItCanSee() {
        checkWindowed(
            document: "Hi. see you at six tomorrow", window: 20, replacement: "Running late.")
    }

    /// The same window with an emoji in the span, where one press moves two units
    /// and a press count would drift.
    func testAWindowedContextWithAnEmojiInTheSpan() {
        checkWindowed(
            document: "Hi. see you at six 🎉 tomorrow", window: 20, replacement: "Running late.")
    }

    /// And a window wide enough to hold everything answers the same as no window
    /// at all, so the mechanism is not quietly window-dependent.
    func testAWideWindowBehavesLikeNoWindow() {
        checkWindowed(
            document: "Hi. see you at six tomorrow", window: 500, replacement: "Running late.")
    }

    /// A host that refuses the forward caret move may already end the visible
    /// prefix with the same text as the tail. That coincidence must not be read
    /// as a successful move, or rollback shifts the caret into the message.
    func testARefusedForwardMoveWithARepeatedTailLeavesTheCaretAlone() {
        let target = CursorTextTarget(before: "before tail", after: "tail")
        target.refusesForwardMovement = true
        let controller = KeyboardController(target: target)
        controller.aiSourceText = controller.aiTargetText

        controller.applyResult("replacement")

        XCTAssertEqual(target.documentContextBeforeInput, "before tail")
        XCTAssertEqual(target.documentContextAfterInput, "tail")
        XCTAssertEqual(target.document, "before tailtail")
    }

    /// **A selection is one backspace, not one per character.** Against a live
    /// selection `deleteBackward()` removes the selection itself, so the old
    /// character count ate `original.count - 1` more from in front of it: the
    /// broken build turns this document into "heveryone world".
    func testReplacingASelectionLeavesTheTextAroundItAlone() {
        let target = CursorTextTarget(before: "hello ", selecting: "there", after: " world")
        let controller = KeyboardController(target: target)

        XCTAssertEqual(controller.aiTargetText, "there")
        apply("everyone", to: controller)

        XCTAssertEqual(target.document, "hello everyone world")

        // And against a real one, which is where "a selection is one backspace"
        // is a fact about UIKit rather than about the mock.
        let live = LiveTextViewTarget(before: "hello ", selecting: "there", after: " world")
        let liveController = KeyboardController(target: live)
        XCTAssertEqual(liveController.aiTargetText, "there")
        apply("everyone", to: liveController)
        XCTAssertEqual(live.document, "hello everyone world")
    }

    /// **Trailing whitespace is a span, not one space.** `wholeField` trims what it
    /// hands the model, so a length taken from *that* string was short by however
    /// many spaces there were, and the field's first character was stranded ahead
    /// of the replacement: "sSee you at 6.". The span is measured off the document,
    /// which is why it is right here.
    func testTwoTrailingSpacesDoNotStrandTheFirstCharacter() {
        check(
            before: "see you at six  ", replacement: "See you at 6.",
            field: "see you at six", expected: "See you at 6.")
    }

    /// **The field carries on past the cursor.** With the caret mid-message the
    /// model was handed the head alone and the tail was left dangling off the end
    /// of the answer: "Could you send me the deck? send me the deck".
    func testACursorInTheMiddleOfTheFieldReplacesAllOfIt() {
        check(
            before: "hey can you", after: " send me the deck",
            replacement: "Could you send me the deck?",
            field: "hey can you send me the deck", expected: "Could you send me the deck?")
    }

    /// **The defect the widened scope exists for, in the words it was reported
    /// in.** Fix `hi mamiwhat?` to `hi mami what?`, type `up`, and Fix again: with
    /// the sentence as the scope the second run is handed the single word `up`,
    /// because the question mark the *first* Fix inserted is a sentence boundary.
    /// So the model is asked to correct a word with nothing around it and there is
    /// no answer it could give that reaches `hi mami whats up?`.
    ///
    /// This asserts what the second run is *handed*, which is the half that was
    /// broken; what it comes back with is the model's business.
    func testAnEarlierSentenceIsPartOfTheSpan() {
        check(
            before: "hi mami what? up", replacement: "hi mami whats up?",
            field: "hi mami what? up", expected: "hi mami whats up?")
    }

    /// The plainest case of all, and the only one the suite used to cover.
    func testTheCaretAtTheEndWithNothingElseInTheField() {
        check(
            before: "i cant make the standup", replacement: "I can't make the standup.",
            expected: "I can't make the standup.")
    }

    /// Nothing to replace: a reply is inserted where the cursor already is rather
    /// than over anything.
    func testAnEmptySourceInsertsRatherThanDeletes() {
        let target = CursorTextTarget(before: "so ")
        let controller = KeyboardController(target: target)

        controller.aiSourceText = ""
        controller.applyResult("Thursday works for me")

        XCTAssertEqual(target.document, "so Thursday works for me")
    }
}
