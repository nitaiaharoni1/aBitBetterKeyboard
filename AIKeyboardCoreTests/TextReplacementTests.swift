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
private final class CursorTextTarget: TextTarget {
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
}

/// The same protocol, over a real `UITextView`.
///
/// `CursorTextTarget` is a model of a document and this is a document: UIKit's
/// own text storage, its own UTF-16 offsets, its own idea of what one backspace
/// removes. The unit mismatch that destroyed the user's text lived in the gap
/// between a hand-written mock and the real thing, so the same cases run against
/// both and the assertions are identical.
@MainActor
private final class LiveTextViewTarget: TextTarget {
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

    func insertText(_ text: String) { view.insertText(text) }
    func deleteBackward() { view.deleteBackward() }

    func adjustTextPosition(byCharacterOffset offset: Int) {
        guard let end = view.selectedTextRange?.end,
            let moved = view.position(from: end, offset: offset)
        else { return }
        view.selectedTextRange = view.textRange(from: moved, to: moved)
    }
}

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

/// Shift, in the keyboard's own language.
@MainActor
final class UppercasingTests: XCTestCase {

    private func typed(_ character: String, under language: KeyboardLanguage) -> String {
        let target = MockTextTarget()
        let controller = KeyboardController(target: target, language: language)
        controller.shift = .on
        controller.press(.character(character))
        return target.text
    }

    /// **Turkish has two i's and `uppercased()` only knows one.** A locale-less
    /// uppercase turns `i` into `I`, which in Turkish is the capital of the
    /// *dotless* ı — a different letter, and a spelling mistake in every word the
    /// shift key touches. `İstanbul` is the test everyone uses because `Istanbul`
    /// is wrong there in the same way `english` is wrong for `English`.
    func testTurkishShiftProducesTheDottedCapital() {
        XCTAssertEqual(typed("i", under: .turkish), "İ")
        XCTAssertEqual(typed("ı", under: .turkish), "I", "the dotless i capitalises without a dot")
    }

    /// And every other keyboard is byte for byte what it was, because that is the
    /// half a locale-aware uppercase could quietly change.
    func testEveryOtherLanguageIsUnchanged() {
        XCTAssertEqual(typed("i", under: .english), "I")
        XCTAssertEqual(typed("i", under: .german), "I")
        XCTAssertEqual(typed("é", under: .french), "É")
        XCTAssertEqual(typed("α", under: .greek), "Α")
        XCTAssertEqual(typed("б", under: .russian), "Б")
        // Scripts with no case at all come through untouched.
        XCTAssertEqual(typed("א", under: .hebrew), "א")
        XCTAssertEqual(typed("م", under: .arabic), "م")
    }
}

/// Committing a candidate, which is the path that runs most: every space press
/// and every tap on the suggestion row.
///
/// **Nothing covered `replaceCurrentWord` at all**, and it carried the same two
/// defects `replaceTargetText` was rewritten to fix — a delete loop sized in
/// grapheme clusters, and no idea what a selection does to a backspace. The
/// corrections it mangles are this keyboard's own: `שלומ` → `שלום` is
/// `hebrewFinalFormCorrection`, written for Hebrew and pinned by
/// `SuggestionEngineTests`, and it fires on the space bar.
@MainActor
final class CandidateCommitTests: XCTestCase {

    private var autocorrect = true

    override func setUp() {
        super.setUp()
        autocorrect = SharedStore.shared.autocorrect
        SharedStore.shared.autocorrect = true
    }

    override func tearDown() {
        SharedStore.shared.autocorrect = autocorrect
        super.tearDown()
    }

    /// One case, twice: against the model and against a real `UITextView`.
    private func check(
        before: String,
        selecting: String = "",
        after: String = "",
        candidate: String,
        bySpace expectedBySpace: String,
        byTap expectedByTap: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for byTap in [false, true] {
            let mock = CursorTextTarget(
                before: before, selecting: selecting.isEmpty ? nil : selecting, after: after)
            let live = LiveTextViewTarget(before: before, selecting: selecting, after: after)
            let expected = byTap ? expectedByTap : expectedBySpace

            for (target, document, name) in [
                (mock as TextTarget, { mock.document }, "the model"),
                (live as TextTarget, { live.document }, "a real UITextView")
            ] {
                let controller = KeyboardController(target: target)
                let suggestion = Suggestion(text: candidate, language: .english, isDefault: true)
                controller.suggestions = [suggestion]
                if byTap {
                    controller.apply(suggestion)
                } else {
                    controller.press(.space)
                }
                XCTAssertEqual(
                    document(), expected,
                    "\(byTap ? "tap" : "space") against \(name)", file: file, line: line)
            }
        }
    }

    /// **The measured failure, row one.** `שָׁ` is one grapheme cluster and three
    /// presses, so a loop sized `prefix.count` stops one mark short and leaves the
    /// half-deleted letter in front of the candidate: `hi שָשָׁלום`.
    func testHebrewWithNiqqudCommitsWholeCharacters() {
        check(
            before: "hi שָׁלומ", candidate: "שָׁלום",
            bySpace: "hi שָׁלום ", byTap: "hi שָׁלום ")
    }

    /// Arabic: `مُ` is two presses and `مَّ` is three.
    func testArabicHarakatCommitWholeCharacters() {
        check(
            before: "hi مُحَمَّد", candidate: "محمد",
            bySpace: "hi محمد ", byTap: "hi محمد ")
    }

    /// Devanagari: `क्षि` is four presses.
    func testDevanagariConjunctsCommitWholeCharacters() {
        check(
            before: "hi क्षिति", candidate: "क्षति",
            bySpace: "hi क्षति ", byTap: "hi क्षति ")
    }

    /// An emoji in the partial word goes in one press, so a loop sized in UTF-16
    /// would over-delete exactly where the cluster loop under-deletes.
    func testAnEmojiInThePartialWord() {
        check(
            before: "ok 🎉par", candidate: "party",
            bySpace: "ok party ", byTap: "ok party ")
    }

    /// **A live selection, which is the other half of the same bug.** The first
    /// backspace removes the selection and every press after it ate real text:
    /// `hello wor⟦ld mo⟧re` came back `hello wword re`, with the user's `or` gone.
    ///
    /// The rule now is the one typing already follows — replace the selection,
    /// touch nothing outside it. On the space bar that means the space replaces
    /// the selection and no candidate is committed, exactly as on the system
    /// keyboard; on a tap it means the candidate is typed over the selection and
    /// the partial word in front of it is left alone, because with a range
    /// selected there is no word under the cursor.
    func testASelectionIsReplacedAndNothingAroundItIs() {
        check(
            before: "hello wor", selecting: "ld mo", after: "re", candidate: "word",
            bySpace: "hello wor re", byTap: "hello worword re")
    }
}
