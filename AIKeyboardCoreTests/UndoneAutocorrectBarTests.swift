import XCTest

@testable import AIKeyboardCore

/// After the user undoes a space-bar swap, `insertSpace` refuses to put the
/// same correction back this session (`undoneAutocorrectSpellings`) — but
/// nothing told the bar or the idle-completion path, so both went on
/// advertising or silently re-applying a swap that `insertSpace` itself had
/// already agreed never to make again.
@MainActor
final class UndoneAutocorrectBarTests: XCTestCase {

    private var autocorrectLevel = AutocorrectLevel.full
    private var completeOnIdle = false
    private var spaceOnIdle = false

    override func setUp() {
        super.setUp()
        autocorrectLevel = SharedStore.shared.autocorrectLevel
        completeOnIdle = SharedStore.shared.completeOnIdle
        spaceOnIdle = SharedStore.shared.spaceOnIdle
        SharedStore.shared.autocorrectLevel = .full
        SharedStore.shared.completeOnIdle = false
        SharedStore.shared.spaceOnIdle = false
    }

    override func tearDown() {
        SharedStore.shared.autocorrectLevel = autocorrectLevel
        SharedStore.shared.completeOnIdle = completeOnIdle
        SharedStore.shared.spaceOnIdle = spaceOnIdle
        super.tearDown()
    }

    // MARK: The suggestion bar

    /// Undo the swap once, then delete the whole word and retype it from
    /// scratch — past the hand-repair window `isCorrectingWordByHand` protects,
    /// so only `undoneAutocorrectSpellings` is left to answer for it. The bar
    /// must bold the literal keystrokes, the same mechanism the Autocorrect-off
    /// path already uses.
    func testTheBarDoesNotBoldAnUndoneCorrectionOnARetype() {
        let target = CursorTextTarget(before: "helo")
        let controller = KeyboardController(target: target, language: .english)
        controller.refreshSuggestions()
        controller.press(.space)
        XCTAssertEqual(target.document, "hello ", "the correction has to be live")
        controller.press(.backspace)
        XCTAssertEqual(target.document, "helo", "the undo has to be live")

        for _ in 0..<4 { controller.press(.backspace) }
        XCTAssertEqual(
            target.document, "",
            "the word has to be fully retyped, past the hand-repair window")

        controller.shift = .off
        for character in "helo" { controller.press(.character(String(character))) }
        XCTAssertEqual(target.document, "helo")

        XCTAssertEqual(
            controller.suggestions.first(where: \.isDefault)?.text, "helo",
            "the bar bolded "
                + "\(controller.suggestions.first(where: \.isDefault)?.text ?? "nothing") "
                + "for a spelling the user already undid this session")
    }

    /// The control: without a prior undo, the same retype is still corrected —
    /// so a build that simply disabled autocorrect, or one that always pins
    /// slot 0, fails this half.
    func testTheBarStillBoldsTheCorrectionWithoutAPriorUndo() {
        let target = CursorTextTarget(before: "helo")
        let controller = KeyboardController(target: target, language: .english)
        controller.refreshSuggestions()

        XCTAssertEqual(
            controller.suggestions.first(where: \.isDefault)?.text.lowercased(), "hello",
            "without an undo the correction should still be offered as the default")
    }

    // MARK: Idle completion

    /// `idleCompletion` picks the first suggestion that is not the literal
    /// keystrokes, with no idea that this exact prefix is the spelling
    /// `undoAutocorrectIfPending` was just asked to put back. Driven directly
    /// through `performIdleTyping`, the same seam `IdleTypingTests` already
    /// uses, so this needs no timer.
    func testIdleCompletionDoesNotReapplyAnUndoneSwap() {
        SharedStore.shared.completeOnIdle = true
        let target = MockTextTarget(text: "helo")
        let controller = KeyboardController(target: target, language: .english)
        controller.undoneAutocorrectSpellings.insert(SeedLanguageModel.fold("helo"))
        controller.suggestions = [
            Suggestion(text: "helo", language: .english, isDefault: true),
            Suggestion(text: "hello", language: .english)
        ]

        controller.performIdleTyping()

        XCTAssertEqual(
            target.text, "helo",
            "idle completion re-applied a swap the user had already undone this session")
    }

    /// The control half of the idle path — `IdleTypingTests
    /// .testCompleteOnIdleReplacesTheWordWithoutASpace` — is the identical
    /// setup with no prior undo, and it must stay green: that is what proves a
    /// build that disabled idle completion outright fails the case above for
    /// the wrong reason.

    // MARK: How long "this session" lasts

    /// **"This session" was the process, and a keyboard process outlives the
    /// field the user was refusing a correction in.**
    ///
    /// Nothing ever removed from `undoneAutocorrectSpellings`, and iOS keeps one
    /// controller alive across fields and across host apps — so a spelling undone
    /// once in a search box was never corrected again anywhere, in any app, until
    /// the extension happened to be torn down. `prepareForNewDocument()` is where
    /// the rest of the per-field state is retired (`pendingAutocorrectUndo`,
    /// `discardPendingCharacter`), and this belongs with them.
    ///
    /// The word is deleted back to an empty field before the switch on purpose:
    /// that clears `deletedWordPrefix`, so the hand-repair rule cannot be what
    /// suppresses the correction and only the undo ledger is left to answer.
    func testAnUndoneCorrectionIsCommittedAgainInTheNextDocument() {
        let first = CursorTextTarget(before: "helo")
        let controller = KeyboardController(target: first, language: .english)
        controller.refreshSuggestions()
        controller.press(.space)
        XCTAssertEqual(first.document, "hello ", "the correction has to be live")
        controller.press(.backspace)
        XCTAssertEqual(first.document, "helo", "the undo has to be live")
        for _ in 0..<4 { controller.press(.backspace) }
        XCTAssertEqual(
            first.document, "", "the hand-repair window has to be past, not merely stale")

        let second = CursorTextTarget(before: "")
        controller.target = second
        controller.prepareForNewDocument()
        controller.shift = .off
        for character in "helo" { controller.press(.character(String(character))) }
        controller.press(.space)

        XCTAssertEqual(
            second.document, "hello ",
            "a refusal taken in one field followed the user into the next one: "
                + "\(second.document)")
    }

    /// The control: inside one document the refusal stands, which is the whole
    /// point of the ledger. A build that answered the case above by emptying the
    /// set on every keystroke fails here.
    func testAnUndoneCorrectionIsStillRefusedInsideTheSameDocument() {
        let target = CursorTextTarget(before: "helo")
        let controller = KeyboardController(target: target, language: .english)
        controller.refreshSuggestions()
        controller.press(.space)
        XCTAssertEqual(target.document, "hello ")
        controller.press(.backspace)
        XCTAssertEqual(target.document, "helo")
        for _ in 0..<4 { controller.press(.backspace) }
        XCTAssertEqual(target.document, "")

        controller.shift = .off
        for character in "helo" { controller.press(.character(String(character))) }
        controller.press(.space)

        XCTAssertEqual(
            target.document, "helo ",
            "space put back a swap the user had already taken off in this same field: "
                + "\(target.document)")
    }
}
