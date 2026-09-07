import XCTest

@testable import AIKeyboardCore

extension CandidateCommitTests {
    func testSpaceDoesNotRepeatAnUndoneAutocorrect() {
        let control = CursorTextTarget(before: "dont")
        let live = KeyboardController(target: control, language: .english)
        live.personal = PersonalLanguageModel(url: nil)
        live.refreshSuggestions()
        live.press(.space)
        XCTAssertEqual(control.document, "don't ", "the correction has to be live")

        let target = CursorTextTarget(before: "dont")
        let controller = KeyboardController(target: target, language: .english)
        controller.personal = PersonalLanguageModel(url: nil)
        controller.refreshSuggestions()
        controller.press(.space)
        controller.press(.backspace)
        XCTAssertEqual(target.document, "dont")
        controller.press(.space)
        XCTAssertEqual(
            target.document, "dont ",
            "space put the undone correction back: \(target.document)")
    }

    /// A later letter closes the undo. Delete then eats that letter, not the
    /// swapped word.
    func testALaterLetterClearsAutocorrectUndo() {
        let control = CursorTextTarget(before: "dont")
        let live = KeyboardController(target: control, language: .english)
        live.personal = PersonalLanguageModel(url: nil)
        live.refreshSuggestions()
        live.press(.space)
        XCTAssertEqual(control.document, "don't ", "the correction has to be live")

        let target = CursorTextTarget(before: "dont")
        let controller = KeyboardController(target: target, language: .english)
        controller.personal = PersonalLanguageModel(url: nil)
        controller.shift = .off
        controller.refreshSuggestions()
        controller.press(.space)
        controller.press(.character("x"))
        controller.press(.backspace)
        XCTAssertEqual(
            target.document, "don't ",
            "delete undid an earlier word: \(target.document)")
    }

    /// Autocorrect-off never swapped, so delete is an ordinary backspace.
    func testAutocorrectOffHasNoUndoPath() {
        SharedStore.shared.userDefaults.set(
            AutocorrectLevel.off.rawValue, forKey: SharedStore.Key.autocorrectLevel)
        XCTAssertEqual(SharedStore.shared.autocorrectLevel, .full)
        XCTAssertEqual(SharedStore.shared.storedAutocorrectLevel, .off)

        let target = CursorTextTarget(before: "dont")
        let controller = KeyboardController(target: target, language: .english)
        controller.personal = PersonalLanguageModel(url: nil)
        controller.refreshSuggestions()
        controller.press(.space)
        XCTAssertEqual(target.document, "dont ", "space swapped while Autocorrect was off")
        controller.press(.backspace)
        XCTAssertEqual(
            target.document, "dont",
            "delete restored a swap that never happened: \(target.document)")
    }

    /// A tap in the host field moves the caret without a key. `selectionDidChange`
    /// is what calls `refreshSuggestions` for that; without it the bar keeps
    /// scoring the word the caret just left.
    func testAHostCaretMoveRefreshesTheBar() {
        let target = CursorTextTarget(before: "hello schedu")
        let controller = KeyboardController(target: target, language: .english)
        controller.press(.backspace)
        let stale = controller.suggestions.map(\.text)
        XCTAssertFalse(stale.isEmpty, "the bar has to have been scoring sched")

        target.placeCaret(before: "hel", after: "lo sched")
        XCTAssertEqual(
            controller.suggestions.map(\.text), stale,
            "the bar moved on its own, so this does not prove the callback")
        controller.refreshSuggestions()
        XCTAssertTrue(
            controller.suggestions.contains { $0.text.lowercased() == "hello" || $0.text == "hel" },
            "the bar is still scoring the word the caret left: \(controller.suggestions.map(\.text))")
    }

    func testPrematureHebrewSpaceIsOfferedOnlyForATap() throws {
        let target = CursorTextTarget(before: "שלו םלכולם")
        let controller = KeyboardController(target: target, language: .hebrew)
        controller.refreshSuggestions()

        XCTAssertEqual(controller.suggestions.count, 1)
        let offer = try XCTUnwrap(controller.suggestions.first)
        XCTAssertEqual(offer.text, "שלום לכולם")
        XCTAssertFalse(offer.isDefault, "space must never commit the boundary repair")
        XCTAssertEqual(offer.commit, .replaceSuffix(expected: "שלו םלכולם"))
        XCTAssertEqual(
            SuggestionBar.candidateHint(offer, replacesSelection: false),
            "Repairs a misplaced space")

        controller.suggestions = [
            Suggestion(
                text: offer.text,
                language: offer.language,
                isDefault: true,
                commit: offer.commit)
        ]
        controller.press(.space)
        XCTAssertEqual(target.document, "שלו םלכולם ", "space applied a tap-only repair")
    }

    func testTappingBoundaryRepairCanBeUndoneBackToItsExactSource() throws {
        let target = CursorTextTarget(before: "אמר שלו םלכולם")
        let controller = KeyboardController(target: target, language: .hebrew)
        controller.refreshSuggestions()
        let offer = try XCTUnwrap(controller.suggestions.first)

        controller.apply(offer)
        XCTAssertEqual(target.document, "אמר שלום לכולם")
        XCTAssertEqual(controller.revertibleEdit?.origin, .spacing)
        XCTAssertEqual(controller.revertibleEdit?.origin.undoLabel, "Undo spacing")

        controller.revertEdit()
        XCTAssertEqual(target.document, "אמר שלו םלכולם")
    }

    func testAStaleBoundaryRepairDoesNotDeleteNewerText() throws {
        let target = CursorTextTarget(before: "שלו ם")
        let controller = KeyboardController(target: target, language: .hebrew)
        controller.refreshSuggestions()
        let stale = try XCTUnwrap(controller.suggestions.first)

        target.placeCaret(before: "שלו םא")
        controller.apply(stale)

        XCTAssertEqual(target.document, "שלו םא")
        XCTAssertNil(controller.revertibleEdit)
    }

    func testAStaleBoundaryRepairDoesNotDeleteIntoTextAfterTheCaret() throws {
        let target = CursorTextTarget(before: "שלו ם")
        let controller = KeyboardController(target: target, language: .hebrew)
        controller.refreshSuggestions()
        let stale = try XCTUnwrap(controller.suggestions.first)

        target.placeCaret(before: "שלו ם", after: "א")
        controller.apply(stale)

        XCTAssertEqual(target.document, "שלו םא")
        XCTAssertNil(controller.revertibleEdit)
    }

    func testBoundaryRepairRequiresAvailableAfterCaretContext() throws {
        let target = CursorTextTarget(before: "שלו ם")
        target.afterContextIsAvailable = false
        let controller = KeyboardController(target: target, language: .hebrew)
        controller.refreshSuggestions()
        XCTAssertFalse(controller.suggestions.contains { $0.commit != .contextual })

        target.afterContextIsAvailable = true
        controller.refreshSuggestions()
        let stale = try XCTUnwrap(controller.suggestions.first)
        target.afterContextIsAvailable = false
        controller.apply(stale)

        XCTAssertEqual(target.document, "שלו ם")
        XCTAssertNil(controller.revertibleEdit)
    }

    func testBoundaryRepairRollsBackAPartialDeletion() throws {
        let target = CursorTextTarget(before: "שלו ם")
        let controller = KeyboardController(target: target, language: .hebrew)
        controller.refreshSuggestions()
        let offer = try XCTUnwrap(controller.suggestions.first)
        target.backwardDeleteLimit = 2

        controller.apply(offer)

        XCTAssertEqual(target.document, "שלו ם")
        XCTAssertNil(controller.revertibleEdit)
    }

    func testBoundaryRepairUndoRollsBackAPartialDeletion() throws {
        let target = CursorTextTarget(before: "אמר שלו םלכולם")
        let controller = KeyboardController(target: target, language: .hebrew)
        controller.refreshSuggestions()
        let offer = try XCTUnwrap(controller.suggestions.first)
        controller.apply(offer)
        XCTAssertEqual(target.document, "אמר שלום לכולם")

        target.backwardDeleteLimit = 2
        controller.revertEdit()

        XCTAssertEqual(target.document, "אמר שלום לכולם")
        XCTAssertNil(controller.revertibleEdit)
    }

    func testBoundaryRepairUndoRefusesADifferentDocument() throws {
        let target = CursorTextTarget(before: "אמר שלו םלכולם")
        let controller = KeyboardController(target: target, language: .hebrew)
        controller.refreshSuggestions()
        let offer = try XCTUnwrap(controller.suggestions.first)
        controller.apply(offer)
        XCTAssertEqual(target.document, "אמר שלום לכולם")

        target.documentIdentifier = UUID()
        controller.revertEdit()

        XCTAssertEqual(target.document, "אמר שלום לכולם")
        XCTAssertNil(controller.revertibleEdit)
    }

    func testBoundaryRepairIsNotOfferedAcrossASelectionOrIntoAWord() {
        let continuing = KeyboardController(
            target: CursorTextTarget(before: "שלו ם", after: "א"), language: .hebrew)
        continuing.refreshSuggestions()
        XCTAssertFalse(
            continuing.suggestions.contains { $0.commit != .contextual },
            "a repair was offered inside a continuing word")

        let selected = KeyboardController(
            target: CursorTextTarget(before: "שלו ם", selecting: "א"), language: .hebrew)
        selected.refreshSuggestions()
        XCTAssertFalse(
            selected.suggestions.contains { $0.commit != .contextual },
            "a repair was offered while text was selected")
    }

    func testBoundaryRepairRespectsThePredictionsSetting() {
        SharedStore.shared.userDefaults.set(false, forKey: SharedStore.Key.predictions)
        let controller = KeyboardController(
            target: CursorTextTarget(before: "שלו ם"), language: .hebrew)
        controller.refreshSuggestions()
        XCTAssertTrue(controller.suggestions.isEmpty)
    }
}
