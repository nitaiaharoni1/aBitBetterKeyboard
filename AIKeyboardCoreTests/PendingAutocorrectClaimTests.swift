import XCTest

@testable import AIKeyboardCore

/// `pendingAutocorrectUndo` remembers one space-bar swap so the very next
/// backspace can restore the keystrokes. The only claim check used to be
/// `contextBefore.hasSuffix(replacement + " ")` — position- and
/// document-blind — with no guard against a selection sitting over the claim.
/// Each case here carries a control that types the same word, so a build that
/// simply turned autocorrect off fails both halves, in `CandidateCommitTests`'
/// own style.
@MainActor
final class PendingAutocorrectClaimTests: XCTestCase {

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

    // MARK: (a) An unrelated occurrence of the replacement

    /// **The measured defect.** A caret tapped after *any* other occurrence of
    /// "don't " anywhere in the document satisfied the old suffix check and
    /// resurrected `dont` there — rewriting a word the swap never touched.
    func testATappedCaretAfterAnUnrelatedOccurrenceDoesNotFireTheUndo() {
        let target = CursorTextTarget(before: "don't and dont")
        let controller = KeyboardController(target: target, language: .english)
        controller.personal = PersonalLanguageModel(url: nil)
        controller.refreshSuggestions()
        controller.press(.space)
        XCTAssertEqual(
            target.document, "don't and don't ", "the correction has to be live")

        // Tap the caret to sit right after the pre-existing, unrelated "don't ".
        target.placeCaret(before: "don't ", after: "and don't ")
        controller.refreshSuggestions()

        controller.press(.backspace)

        XCTAssertEqual(
            target.document, "don'tand don't ",
            "backspace at an unrelated \"don't \" must delete a character, not "
                + "resurrect \"dont\" there: \(target.document)")
    }

    // MARK: (b) A selection right after a fresh swap

    /// **The measured defect.** Backspace over a selection did not check for
    /// one at all: the old claim check passed, `target.deleteBackward()`
    /// consumed the selection, and the code went on to resurrect `dont` beside
    /// it — deleting real, selected text *and* putting the wrong word back.
    func testBackspaceOverASelectionRightAfterAFreshSwapDoesNotResurrectTheOriginal() {
        let target = CursorTextTarget(before: "dont")
        let controller = KeyboardController(target: target, language: .english)
        controller.personal = PersonalLanguageModel(url: nil)
        controller.refreshSuggestions()
        controller.press(.space)
        XCTAssertEqual(target.document, "don't ", "the correction has to be live")

        target.insertText("world")
        XCTAssertEqual(target.document, "don't world")
        // The user selects the word they just typed, right after the swap.
        target.select("world", before: "don't ", after: "")

        controller.press(.backspace)

        XCTAssertEqual(
            target.document, "don't ",
            "backspace over the selection must delete only the selection, not "
                + "resurrect \"dont\": \(target.document)")
    }

    // MARK: (c) A document switch

    /// **The measured defect.** The pair survives a field or app switch —
    /// iOS keeps one controller across both — and fires in a different
    /// document that merely ends the same way. Chosen to read identically at
    /// the caret to the first document, so the exact-context match from (a)
    /// alone cannot be what protects it: only retiring the pair on the switch
    /// itself can.
    func testPendingUndoDoesNotSurviveADocumentSwitchEvenWhenTheContextMatchesExactly() {
        let first = MockTextTarget(text: "dont")
        let controller = KeyboardController(target: first, language: .english)
        controller.personal = PersonalLanguageModel(url: nil)
        let firstIdentity = (first as TextTarget).documentIdentifier
        XCTAssertNotNil(firstIdentity)
        XCTAssertEqual(controller.target?.documentIdentifier, firstIdentity)
        controller.refreshSuggestions()
        controller.press(.space)
        XCTAssertEqual(first.text, "don't ", "the correction has to be live")

        let second = MockTextTarget(text: "don't ")
        XCTAssertNotEqual(firstIdentity, (second as TextTarget).documentIdentifier)
        controller.target = second
        controller.prepareForNewDocument()

        controller.press(.backspace)

        XCTAssertEqual(
            second.text, "don't",
            "a document switch must retire the undo even when the new context "
                + "reads identically: \(second.text)")
        XCTAssertEqual(
            controller.personal.observationCount(of: "don't", in: .english, source: .automatic), 1,
            "preparing the new document must accept the captured learning once")
    }

    // MARK: (d) A proxy that echoes stale context right after the write

    /// **Round 2: the snapshot itself must never be a post-write proxy read.**
    /// Every fixture above answers `documentContextBeforeInput` honestly on
    /// every read, so a snapshot built by re-asking the proxy right after the
    /// swap's own space landed passed the whole suite while being wrong on a
    /// real, asynchronously echoing host — `insertCommittalSpace`'s own doc
    /// comment already names that staleness. `StaleEchoTarget` reproduces it:
    /// the read immediately after `target?.insertText(" ")` answers the
    /// pre-write value, so a snapshot re-asked there captures the swap with no
    /// trailing space and every later, honest read then disagrees with it
    /// forever. Built locally from the pre-swap read instead, the snapshot is
    /// correct from the moment it is taken and the undo survives.
    func testTheUndoSnapshotSurvivesAProxyThatEchoesStaleContextRightAfterTheWrite() {
        let target = StaleEchoTarget(before: "dont")
        let controller = KeyboardController(target: target, language: .english)
        controller.personal = PersonalLanguageModel(url: nil)
        controller.refreshSuggestions()
        controller.press(.space)
        XCTAssertEqual(target.document, "don't ", "the correction has to be live")

        controller.press(.backspace)

        XCTAssertEqual(
            target.document, "dont",
            "the first backspace after a swap must restore the typed word even "
                + "when the proxy echoed stale context right after the space "
                + "landed: \(target.document)")
    }

    // MARK: (e) Provisional learning

    func testAutocorrectLearningWaitsUntilTheUndoWindowMovesOn() {
        let target = MockTextTarget(text: "dont")
        let controller = KeyboardController(target: target, language: .english)
        controller.personal = PersonalLanguageModel(url: nil)
        controller.refreshSuggestions()

        controller.press(.space)

        XCTAssertEqual(target.text, "don't ", "the correction has to be live")
        XCTAssertEqual(
            controller.personal.observationCount(of: "don't", in: .english, source: .automatic), 0,
            "an autocorrect that can still be undone must not be learned yet")

        controller.press(.character("w"))

        XCTAssertEqual(
            controller.personal.observationCount(of: "don't", in: .english, source: .automatic), 1,
            "the first same-document move-on must finalize the staged replacement once")
    }

    func testImmediateAutocorrectUndoDiscardsTheStagedLearning() {
        let target = MockTextTarget(text: "dont")
        let controller = KeyboardController(target: target, language: .english)
        controller.personal = PersonalLanguageModel(url: nil)
        controller.refreshSuggestions()
        controller.press(.space)

        controller.press(.backspace)
        controller.press(.character("w"))

        XCTAssertEqual(target.text, "dontw")
        XCTAssertEqual(
            controller.personal.observationCount(of: "don't", in: .english, source: .automatic), 0,
            "taking the automatic replacement back must discard its staged learning")
    }

    func testIdentityChangeAcceptsLearningOnceButCannotUndoInTheNewDocument() {
        let first = MockTextTarget(text: "dont")
        let controller = KeyboardController(target: first, language: .english)
        controller.personal = PersonalLanguageModel(url: nil)
        controller.refreshSuggestions()
        controller.press(.space)
        XCTAssertEqual(first.text, "don't ", "the correction has to be live")

        let second = MockTextTarget(text: "don't ")
        controller.attach(target: second)
        controller.refreshSuggestions()

        XCTAssertEqual(
            controller.personal.observationCount(of: "don't", in: .english, source: .automatic), 1,
            "an identity mismatch must accept the captured observation exactly once")

        controller.press(.backspace)

        XCTAssertEqual(second.text, "don't", "backspace must not undo into the new document")
        XCTAssertEqual(
            controller.personal.observationCount(of: "don't", in: .english, source: .automatic), 1,
            "refreshing and backspace must not accept the same observation twice")
    }

    func testAcceptingAStagedClaimDoesNotClearAnotherDocumentsOpenWord() {
        let first = MockTextTarget(text: "dont")
        let controller = KeyboardController(target: first, language: .english)
        controller.personal = PersonalLanguageModel(url: nil)
        controller.refreshSuggestions()
        controller.press(.space)

        let second = MockTextTarget(text: "world")
        controller.target = second
        controller.adoptOpenWord()
        XCTAssertEqual(controller.openWord, "world")

        controller.retirePendingAutocorrectUndoIfDocumentChanged()
        XCTAssertEqual(controller.personal.observationCount(of: "don't", in: .english, source: .automatic), 1)
        XCTAssertEqual(controller.openWord, "world")

        second.text = ""
        controller.refreshSuggestions()
        controller.refreshSuggestions()

        XCTAssertEqual(controller.personal.observationCount(of: "don't", in: .english, source: .automatic), 1)
        XCTAssertEqual(controller.personal.count(of: "world", in: .english), 1)
    }

    func testStagedLearningStoresTheCorrectedWordWithoutItsEdgeMark() {
        let target = MockTextTarget(text: "recieve,")
        let controller = KeyboardController(target: target, language: .english)
        controller.personal = PersonalLanguageModel(url: nil)
        controller.refreshSuggestions()
        controller.press(.space)
        XCTAssertEqual(target.text, "receive, ")

        controller.press(.character("x"))

        XCTAssertEqual(
            controller.personal.observationCount(of: "receive", in: .english, source: .automatic), 1)
        XCTAssertEqual(
            controller.personal.observationCount(of: "receive,", in: .english, source: .automatic), 0)
    }
}
