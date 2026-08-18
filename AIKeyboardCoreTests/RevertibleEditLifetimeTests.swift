import XCTest

@testable import AIKeyboardCore

/// How long the way back from a Fix, a Rewrite, a Reply or a pasted clip lasts,
/// and what it does when it is taken late.
///
/// **It used to last exactly one keystroke.** That was safe for one reason and
/// one only: the revert replaced the whole field with what had been there before,
/// so surviving a keystroke meant offering to delete whatever had been typed
/// since. It was also far too short for what the control exists for — NIT-154
/// records ten autocorrections a session committing a real word nobody intended,
/// and a wrong word is noticed while the *sentence* is read, several words after
/// it lands.
///
/// So the lifetime is now a question about the document rather than a count of
/// keystrokes: the edit stands for as long as what it wrote can be found, exactly
/// once, where it wrote it. `RevertibleEdit.rebased(onto:)` and
/// `spanUndo(behind:)` are that question and are pure, which is why this file can
/// ask it directly. Every assertion below names what the *shipped* build answers.
final class RevertibleEditLifetimeTests: XCTestCase {

    private func fix(previous: String, applied: String) -> RevertibleEdit {
        RevertibleEdit(origin: .ai(.fix), previous: previous, applied: applied, undo: .wholeField)
    }

    private func paste(_ applied: String) -> RevertibleEdit {
        RevertibleEdit(origin: .clip, previous: "", applied: applied, undo: .spanAtCursor)
    }

    // MARK: A whole-field edit

    /// Nothing typed since: the field becomes what it was.
    func testAWholeFieldUndoWithNothingTypedSinceIsThePlainReplacement() {
        let edit = fix(previous: "i cant make it", applied: "I can't make it.")
        XCTAssertEqual(edit.rebased(onto: "I can't make it."), "i cant make it")
    }

    /// **The one that made the longer life safe.** A build that simply stopped
    /// clearing the edit would still put `previous` back as the whole field and
    /// answer `i cant make it` here — deleting ` see you thursday`, which the user
    /// typed and the keyboard never touched.
    func testAWholeFieldUndoKeepsWhatWasTypedAfterIt() {
        let edit = fix(previous: "i cant make it", applied: "I can't make it.")
        XCTAssertEqual(
            edit.rebased(onto: "I can't make it. see you thursday"),
            "i cant make it see you thursday")
    }

    /// Typed *in front of* it as well, which is what a caret moved back and a
    /// sentence added before the correction looks like.
    func testAWholeFieldUndoKeepsWhatWasTypedInFrontOfItToo() {
        let edit = fix(previous: "i cant make it", applied: "I can't make it.")
        XCTAssertEqual(
            edit.rebased(onto: "hey — I can't make it."), "hey — i cant make it")
    }

    /// Typed over, deleted into, or the host replaced the field: there is nothing
    /// to put back and nowhere to put it, so the offer goes away.
    func testAWholeFieldUndoRefusesWhenWhatItWroteIsGone() {
        let edit = fix(previous: "i cant make it", applied: "I can't make it.")
        XCTAssertNil(edit.rebased(onto: "I can't make it"), "one character short is still gone")
        XCTAssertNil(edit.rebased(onto: ""), "an emptied field — the message was sent")
        XCTAssertNil(edit.rebased(onto: "something else entirely"))
    }

    /// **Two occurrences is a refusal, not a coin toss.** A one-word correction
    /// repeats easily, and replacing the wrong one changes a word the user typed.
    func testAWholeFieldUndoRefusesWhenItCannotTellWhichOccurrenceItWrote() {
        let edit = RevertibleEdit(
            origin: .ai(.fix), previous: "recieve", applied: "receive", undo: .wholeField)
        XCTAssertEqual(edit.rebased(onto: "receive it"), "recieve it")
        XCTAssertNil(
            edit.rebased(onto: "receive it and receive the other one"),
            "the undo picked one of two occurrences to rewrite")
    }

    /// The bound is about the suggestion bar rather than about safety: the control
    /// costs the three candidate slots about 52pt for as long as it is up. Asked
    /// either side of the limit so a build that drops the bound fails.
    func testTheOfferExpiresOnceAWholeLineHasBeenWrittenSince() {
        let edit = fix(previous: "i cant make it", applied: "I can't make it.")
        let allowed = String(repeating: "x", count: RevertibleEdit.charactersOfTypingAllowed)

        XCTAssertNotNil(edit.rebased(onto: "I can't make it." + allowed))
        XCTAssertNil(edit.rebased(onto: "I can't make it." + allowed + "x"))
    }

    // MARK: A span at the cursor

    /// The two shapes the deleted `standsAtEnd(of:)` used to answer as a bool:
    /// the span is the last thing in front of the caret, or the window is so short
    /// that everything visible behind the caret is the tail of it.
    func testASpanUndoStillCoversTheTwoShapesItAlwaysDid() throws {
        let edit = paste("Wednesday at four")

        let atTheEnd = try XCTUnwrap(edit.spanUndo(behind: "see you Wednesday at four"))
        XCTAssertEqual(atTheEnd.delete, "Wednesday at four".utf16.count)
        XCTAssertEqual(atTheEnd.insert, "")

        // A clip longer than the window iOS hands back: what is visible is a
        // suffix of what was pasted.
        let truncated = try XCTUnwrap(edit.spanUndo(behind: "esday at four"))
        XCTAssertEqual(truncated.delete, "Wednesday at four".utf16.count)
    }

    /// **The new one.** What was typed after the paste is deleted and typed back
    /// unchanged around the swap, because `UITextDocumentProxy` deletes backwards
    /// from the caret and cannot address a range — so reaching the span means
    /// passing through those characters.
    func testASpanUndoReachesBackPastWhatWasTypedAfterIt() throws {
        let edit = paste("Wednesday at four")
        let step = try XCTUnwrap(edit.spanUndo(behind: "see you Wednesday at four, ok?"))

        XCTAssertEqual(step.delete, "Wednesday at four, ok?".utf16.count)
        XCTAssertEqual(
            step.insert, ", ok?",
            "the undo would have deleted `, ok?` and not typed it back")
    }

    /// A reply put back over a selection is the case where `previous` is not
    /// empty, and both halves have to survive the trip.
    func testASpanUndoPutsBackWhatTheSelectionHeld() throws {
        let edit = RevertibleEdit(
            origin: .ai(.fix), previous: "wrold", applied: "world", undo: .spanAtCursor)
        let step = try XCTUnwrap(edit.spanUndo(behind: "hello there world friend"))

        XCTAssertEqual(step.delete, "world friend".utf16.count)
        XCTAssertEqual(step.insert, "wrold friend")
    }

    /// An empty window is refused, because `""` is a suffix of every string and
    /// deleting a count from a field the keyboard cannot see is the one outcome
    /// worse than no undo at all.
    func testASpanUndoRefusesWhatItCannotFind() {
        let edit = paste("Wednesday at four")
        XCTAssertNil(edit.spanUndo(behind: ""))
        XCTAssertNil(edit.spanUndo(behind: "see you tomorrow"))
        XCTAssertNil(
            edit.spanUndo(behind: "Wednesday at four and Wednesday at four"),
            "the undo picked one of two pastes to take out")
    }

    /// The two shapes answer for themselves and never for each other: a
    /// `.wholeField` edit asked for a span undo would delete a count of units from
    /// wherever the caret happened to be, which is how `hello there wrold friend`
    /// became the single word `wrold`.
    func testNeitherShapeAnswersForTheOther() {
        let whole = fix(previous: "i cant make it", applied: "I can't make it.")
        let span = paste("Wednesday at four")

        XCTAssertNil(whole.spanUndo(behind: "I can't make it."))
        XCTAssertNil(span.rebased(onto: "see you Wednesday at four"))
    }
}
