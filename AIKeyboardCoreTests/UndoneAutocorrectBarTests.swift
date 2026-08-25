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
}
