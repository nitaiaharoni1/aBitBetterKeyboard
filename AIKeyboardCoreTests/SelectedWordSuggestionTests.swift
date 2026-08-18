import XCTest

@testable import AIKeyboardCore

/// A whole word selected in the host's field, which is how somebody asks this
/// keyboard "what else could this word be".
///
/// **The bar answered about something else entirely.** With a range selected,
/// `documentContextBeforeInput` stops at the *start* of it, so
/// `currentWordPrefix` is whatever sits in front of the selection — for a
/// double-tapped word, nothing at all. The engine was therefore asked for
/// next-word predictions in the middle of a sentence the user had just pointed
/// at, and the one word they were asking about was the one word the bar could
/// not see.
///
/// Every assertion below was written against what the previous build returned
/// for the same input. That matters here more than usual, because the engine
/// echoes what it was scored on as candidate zero: `XCTAssertFalse(isEmpty)` and
/// "some candidate starts with the selection" are both true of a bar that never
/// looked at the selection at all.
@MainActor
final class SelectedWordSuggestionTests: XCTestCase {

    private var autocorrectLevel = AutocorrectLevel.full
    private var predictions = true

    override func setUp() {
        super.setUp()
        autocorrectLevel = SharedStore.shared.autocorrectLevel
        predictions = SharedStore.shared.predictions
        SharedStore.shared.autocorrectLevel = .full
        SharedStore.shared.predictions = true
    }

    override func tearDown() {
        SharedStore.shared.autocorrectLevel = autocorrectLevel
        SharedStore.shared.predictions = predictions
        super.tearDown()
    }

    /// The words the bar actually draws, in the order it draws them.
    private func drawnWords(_ controller: KeyboardController) -> [String] {
        SuggestionBar.centeredSlots(
            controller.suggestions, typed: controller.wordUnderConsideration
        )
        .compactMap { $0?.text }
    }

    // MARK: What is scored

    /// The whole feature. `recieve` is one of `UITextChecker`'s own corrections,
    /// so the only thing standing between the user and it was which string the
    /// engine was handed.
    ///
    /// The old build scored `""` — next-word predictions for "please " — and
    /// `receive` could not appear in that list under any ranking.
    func testAWholeSelectedWordIsWhatTheBarScores() {
        let target = CursorTextTarget(before: "please ", selecting: "recieve", after: " it")
        let controller = KeyboardController(target: target, language: .english)
        controller.refreshSuggestions()

        XCTAssertEqual(controller.wordUnderConsideration, "recieve")
        XCTAssertTrue(
            drawnWords(controller).contains { $0.lowercased() == "receive" },
            "got \(drawnWords(controller)) — the old bar drew next-word predictions "
                + "for the space in front of the selection")
    }

    /// Hebrew reaches its correction through this keyboard's own rule rather
    /// than through Apple's checker, which reports `שלומ` as a fine word, so a
    /// selection has to arrive at the engine for that rule to fire at all.
    func testAWholeSelectedHebrewWordIsScoredToo() {
        let target = CursorTextTarget(before: "אמרתי ", selecting: "שלומ", after: " לכולם")
        let controller = KeyboardController(target: target, language: .hebrew)
        controller.refreshSuggestions()

        XCTAssertTrue(
            drawnWords(controller).contains("שלום"),
            "got \(drawnWords(controller))")
    }

    /// A mark at the edge of the selection is not part of the word, and the
    /// engine already knows that — `wordCore` is what every source is asked
    /// about. This is here because the *replacement* has to put the mark back,
    /// which the test below asserts, and both halves have to agree about where
    /// the word ends.
    func testAnOpeningBracketInFrontOfTheSelectionIsNotAWordJoinedToIt() {
        let target = CursorTextTarget(before: "he said (", selecting: "recieve", after: ")")
        let controller = KeyboardController(target: target, language: .english)

        XCTAssertEqual(controller.selectedWord, "recieve")
        controller.refreshSuggestions()
        XCTAssertTrue(
            drawnWords(controller).contains { $0.lowercased() == "receive" },
            "got \(drawnWords(controller))")
    }

    /// **Part of a word is a different question, and any answer to it would be
    /// typed over half a word.** All four shapes reach the engine as the word
    /// behind the cursor instead, which is what shipped and is still right:
    /// `SuggestionEngine` is being asked about keystrokes there, not about a
    /// word somebody pointed at.
    func testASelectionThatIsNotAWholeWordIsNotScoredAsOne() {
        let cases: [(String, String, String, String)] = [
            ("rec", "ieve", "", "a word joined to the leading end"),
            ("", "recie", "ve", "a word joined to the trailing end"),
            ("", "don", "'t", "an apostrophe stays inside a word"),
            ("hello wor", "ld mo", "re", "more than one token")
        ]
        for (before, selecting, after, why) in cases {
            let target = CursorTextTarget(before: before, selecting: selecting, after: after)
            let controller = KeyboardController(target: target, language: .english)
            XCTAssertNil(controller.selectedWord, why)
            XCTAssertEqual(controller.wordUnderConsideration, controller.currentWordPrefix, why)
        }
    }

    // MARK: What is drawn

    /// **Nothing in the bar is bold over a selection, because nothing is
    /// "inserted when you press space".** Space types a space over a range, the
    /// way it does on the system keyboard, and `insertSpace` refuses the commit
    /// there — so a bold slot would advertise a swap that cannot happen, and
    /// under `centeredSlots`' echo rule it would spend the middle slot drawing
    /// the very word the user selected.
    func testNothingIsBoldAndTheSelectedWordIsNotOfferedBack() {
        let target = CursorTextTarget(before: "please ", selecting: "recieve", after: " it")
        let controller = KeyboardController(target: target, language: .english)
        controller.refreshSuggestions()

        XCTAssertFalse(
            controller.suggestions.contains(where: \.isDefault),
            "space cannot commit over a selection, so no candidate may be marked as the "
                + "one it commits")
        XCTAssertFalse(
            drawnWords(controller).contains { SuggestionEngine.comparable($0) == "recieve" },
            "got \(drawnWords(controller)) — the selected word is in the field and "
                + "highlighted in it; a slot spent on it is a tap that changes nothing")
        // Or an empty bar would satisfy both of the assertions above.
        XCTAssertFalse(drawnWords(controller).isEmpty)
    }

    // MARK: What a tap does

    /// **No trailing space, because a selected word is repaired in place.** The
    /// spacing around it is already in the field: the build that inserted one
    /// answered `please receive  it`, with two spaces in the middle of somebody's
    /// message.
    func testTappingACandidateReplacesTheSelectionWithNoTrailingSpace() {
        let mock = CursorTextTarget(before: "please ", selecting: "recieve", after: " it")
        let live = LiveTextViewTarget(before: "please ", selecting: "recieve", after: " it")
        for (target, document, name) in [
            (mock as TextTarget, { mock.document }, "the model"),
            (live as TextTarget, { live.document }, "a real UITextView")
        ] {
            let controller = KeyboardController(target: target, language: .english)
            controller.apply(Suggestion(text: "receive", language: .english))
            XCTAssertEqual(document(), "please receive it", "against \(name)")
        }
    }

    /// The mark the selection was wearing comes back, for the same reason the
    /// caret path restores it: the engine was asked about `wordCore`, so the
    /// candidate never carries it and inserting the candidate bare deletes it.
    func testAMarkAtTheEdgeOfTheSelectionSurvivesTheReplacement() {
        let target = CursorTextTarget(before: "please ", selecting: "recieve,", after: " it")
        let controller = KeyboardController(target: target, language: .english)
        controller.apply(Suggestion(text: "receive", language: .english))
        XCTAssertEqual(target.document, "please receive, it")
    }

    /// **A word picked over a selection is hand-placed, and the next space must
    /// not overrule it.** The tap leaves the caret inside the sentence with no
    /// space after it, so the very next key can be one — and `commitReason`
    /// knows nothing about how the word got there. `teh` is the case the
    /// neighbour rule commits on purpose (`teh` → `the`), so a build without the
    /// protection replaces a word the user chose by hand one keystroke later.
    func testTheWordPickedOverASelectionIsNotSwappedByTheNextSpace() {
        let target = CursorTextTarget(before: "say ", selecting: "hello")
        let controller = KeyboardController(target: target, language: .english)
        controller.apply(Suggestion(text: "teh", language: .english))
        XCTAssertEqual(target.document, "say teh", "the tap itself")

        controller.press(.space)
        XCTAssertEqual(
            target.document, "say teh ",
            "the space bar corrected a word the user picked out of the bar; the build "
                + "without the hand-placed snapshot answers `say the `")
    }

    /// **A range spanning two words gets no marks back.** `wordCore` trims the
    /// full stop off `hello world.` and there is no word for it to belong to, so
    /// the restoration is scoped to a whole selected word. The build that asked
    /// it of every selection answered `the.` here.
    func testAMultiWordSelectionIsReplacedExactlyAsItStands() {
        let target = CursorTextTarget(before: "say ", selecting: "hello world.", after: " now")
        let controller = KeyboardController(target: target, language: .english)
        XCTAssertNil(controller.selectedWord, "two tokens are not a word")
        controller.apply(Suggestion(text: "the", language: .english))
        // The second space is the partial-selection behaviour that shipped and
        // that `CandidateCommitTests.testASelectionIsReplacedAndNothingAroundItIs`
        // pins; it is not what this test is about. What it is about is that the
        // full stop did not come back glued to `the`.
        XCTAssertEqual(target.document, "say the  now")
    }

    /// A bar with no default read out as three bare words. The hint is the only
    /// thing that says where a tap lands, and over a selection it does not land
    /// where the other two sentences say it does.
    func testTheHintSaysWhereATapLands() {
        let plain = Suggestion(text: "receive", language: .english)
        let bold = Suggestion(text: "receive", language: .english, isDefault: true)
        XCTAssertEqual(
            SuggestionBar.candidateHint(plain, replacesSelection: true),
            "Replaces the selected word")
        XCTAssertEqual(
            SuggestionBar.candidateHint(bold, replacesSelection: true),
            "Replaces the selected word",
            "space commits nothing over a range, so the space sentence must not win here")
        XCTAssertEqual(
            SuggestionBar.candidateHint(bold, replacesSelection: false),
            "Inserted when you press space")
        XCTAssertEqual(SuggestionBar.candidateHint(plain, replacesSelection: false), "")
    }

    /// The control half of the case above: the same word *typed* is not
    /// protected, or this would be a keyboard with autocorrect switched off.
    func testTheSameWordTypedIsStillCorrectedOnSpace() {
        let target = CursorTextTarget(before: "say ")
        let controller = KeyboardController(target: target, language: .english)
        // A fresh controller arms shift for the start of a sentence, and this
        // one is typing in the middle of somebody else's.
        controller.shift = .off
        for character in "teh" { controller.press(.character(String(character))) }
        controller.press(.space)
        XCTAssertEqual(target.document, "say the ")
    }
}
