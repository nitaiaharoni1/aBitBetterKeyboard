import UIKit
import XCTest

@testable import AIKeyboardCore

/// Where the answer from an AI action lands in the document.
///
/// D6 puts Rewrite one tap away in the suggestion row, which is what makes these
/// reachable: before it, every one of them needed the user to open a panel first.
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
        sentence: String? = nil,
        expected: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let mock = CursorTextTarget(before: before, after: after)
        let mockController = KeyboardController(target: mock)
        if let sentence {
            XCTAssertEqual(mockController.aiTargetText, sentence, file: file, line: line)
        }
        apply(replacement, to: mockController)
        XCTAssertEqual(mock.document, expected, "against the model", file: file, line: line)

        let live = LiveTextViewTarget(before: before, after: after)
        let liveController = KeyboardController(target: live)
        if let sentence {
            XCTAssertEqual(liveController.aiTargetText, sentence, file: file, line: line)
        }
        apply(replacement, to: liveController)
        XCTAssertEqual(live.document, expected, "against a real UITextView", file: file, line: line)
    }

    // MARK: A character is not a character

    /// **An emoji in front of the caret used to eat the sentence before it.** The
    /// step over the tail counted grapheme clusters and the host counts UTF-16, so
    /// the cursor stopped one unit short of the end while the backspace loop ran
    /// the full length: `Hi. hey 😊 six` came back as `Hi.Replacementx`.
    func testAnEmojiInTheTailDoesNotEatTheSentenceBefore() {
        check(
            before: "Hi. hey ", after: "😊 six", replacement: "Replacement",
            sentence: "hey 😊 six", expected: "Hi. Replacement")
    }

    /// A flag is one grapheme and four UTF-16 units — the widest gap of the lot.
    func testAFlagInTheTail() {
        check(
            before: "Hi. from ", after: "🇮🇱 today", replacement: "From Israel today.",
            sentence: "from 🇮🇱 today", expected: "Hi. From Israel today.")
    }

    /// A ZWJ sequence is one grapheme and five UTF-16 units.
    func testAZeroWidthJoinerSequenceInTheTail() {
        check(
            before: "Hi. ask ", after: "👩‍💻 later", replacement: "I'll ask her later.",
            sentence: "ask 👩‍💻 later", expected: "Hi. I'll ask her later.")
    }

    /// **A decomposed accent, which is the one that reaches ordinary users.**
    /// French, Spanish and Portuguese are three of the fourteen layouts, and text
    /// pasted from the web or typed on a Mac arrives in NFD often enough: `à` as
    /// `a` + U+0300 is one grapheme and two UTF-16 units. The broken build returns
    /// `Bonjour.On se voit à 18hx`.
    func testADecomposedAccentInTheTail() {
        check(
            before: "Bonjour. on se ", after: "voit a\u{0300} six",
            replacement: "On se voit à 18h",
            sentence: "on se voit a\u{0300} six", expected: "Bonjour. On se voit à 18h")
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
            expected: "הי. נדבר בשתיים")
    }

    // MARK: The gap in front of the sentence

    /// **A cursor sitting immediately after a full stop.** The head is then empty,
    /// so the sentence's first real character is in the tail and the space that
    /// separates the two sentences was inside the delete span while staying
    /// outside the string sent to the model: `Hi.See you at 6.`.
    func testTheSeparatorAfterAnEarlierSentenceSurvives() {
        check(
            before: "Hi.", after: " see you at six", replacement: "See you at 6.",
            sentence: "see you at six", expected: "Hi. See you at 6.")
    }

    func testTheSeparatorSurvivesInHebrewToo() {
        check(
            before: "היי.", after: " נדבר בשש", replacement: "נדבר בשש",
            sentence: "נדבר בשש", expected: "היי. נדבר בשש")
    }

    /// Two spaces are two spaces: neither is part of the sentence after them.
    func testADoubleSeparatorIsLeftAlone() {
        check(
            before: "Hi.", after: "  see you at six", replacement: "See you at 6.",
            sentence: "see you at six", expected: "Hi.  See you at 6.")
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
    /// the sentence it can see, exactly, and nothing outside it. The expectation
    /// is built from `aiTargetText` rather than typed out, because the visible
    /// sentence is shorter than the real one here — that is the honest consequence
    /// of a host that hands over a window, and the assertion would otherwise be
    /// asserting the window size rather than the behaviour.
    private func checkWindowed(
        document: String, window: Int, replacement: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let target = CursorTextTarget(before: document, window: window)
        let controller = KeyboardController(target: target)

        let visible = controller.aiTargetText
        XCTAssertFalse(visible.isEmpty, file: file, line: line)
        XCTAssertTrue(
            document.hasSuffix(visible), "the visible sentence has to be the end of the document",
            file: file, line: line)
        apply(replacement, to: controller)

        XCTAssertEqual(
            target.document, String(document.dropLast(visible.count)) + replacement,
            "the loop deleted something other than exactly the sentence it could see",
            file: file, line: line)
    }

    func testAWindowedContextDeletesExactlyTheSentenceItCanSee() {
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

    /// **Trailing whitespace is a span, not one space.** `currentSentence` drops
    /// one trailing space and then trims what is left, so `original.count + 1` was
    /// short by however many more there were, and the sentence's first character
    /// was stranded ahead of the replacement: "sSee you at 6.".
    func testTwoTrailingSpacesDoNotStrandTheFirstCharacter() {
        check(
            before: "see you at six  ", replacement: "See you at 6.",
            sentence: "see you at six", expected: "See you at 6.")
    }

    /// **The sentence carries on past the cursor.** With the caret mid-sentence
    /// the model was handed the head alone and the tail was left dangling off the
    /// end of the answer: "Could you send me the deck? send me the deck".
    func testACursorInTheMiddleOfASentenceReplacesAllOfIt() {
        check(
            before: "hey can you", after: " send me the deck",
            replacement: "Could you send me the deck?",
            sentence: "hey can you send me the deck", expected: "Could you send me the deck?")
    }

    /// The sentence before it is not part of the span, and neither is the space
    /// that separates them. This is the case the old count got right, and it has
    /// to stay right.
    func testAnEarlierSentenceIsUntouched() {
        check(
            before: "Hi. see you at six ", replacement: "See you at 6.",
            sentence: "see you at six", expected: "Hi. See you at 6.")
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
