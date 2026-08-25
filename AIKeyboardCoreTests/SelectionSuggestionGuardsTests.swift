import XCTest

@testable import AIKeyboardCore

/// A live selection has no default at all — space types a space over it, the
/// way it does on the system keyboard — so nothing may ever be marked default
/// while one exists, and nothing that answers about the word behind an older,
/// pre-selection request may land over it either.
@MainActor
final class SelectionSuggestionGuardsTests: XCTestCase {

    private var predictions = true
    private var autocorrectLevel = AutocorrectLevel.full

    override func setUp() {
        super.setUp()
        predictions = SharedStore.shared.predictions
        autocorrectLevel = SharedStore.shared.autocorrectLevel
        SharedStore.shared.predictions = true
        SharedStore.shared.autocorrectLevel = .full
    }

    override func tearDown() {
        SharedStore.shared.predictions = predictions
        SharedStore.shared.autocorrectLevel = autocorrectLevel
        super.tearDown()
    }

    // MARK: Fix 4 — guard order in pinningDefaultToTypedIfNeeded

    /// **The measured defect.** `guard !prefix.isEmpty else { return results }`
    /// ran before the selection strip, so a selection whose scoring prefix is
    /// empty — a word selected together with its trailing space, here — fell
    /// through untouched and kept whatever bold default the empty-prefix
    /// (next-word) tier had drawn, hint and all. `SuggestionEngine` always marks
    /// a default for an empty prefix (`markDefault(promoteToMiddle(results), at:
    /// min(1, results.count - 1))`), so this is not a vacuous check.
    func testASelectionWithAnEmptyScoringPrefixHasNoDefault() {
        // "hello " is selected in full, together with its trailing space, so
        // `selectedWord` (which refuses any whitespace inside the selection)
        // answers nil and the scoring prefix falls back to `currentWordPrefix`,
        // which is also empty: nothing sits before the selection at all.
        let target = CursorTextTarget(before: "", selecting: "hello ", after: "world")
        let controller = KeyboardController(target: target, language: .english)
        XCTAssertNil(controller.selectedWord, "the fixture needs an empty scoring prefix")
        XCTAssertTrue(controller.currentWordPrefix.isEmpty, "the fixture needs an empty scoring prefix")
        XCTAssertNotNil(controller.selection, "the fixture needs a live selection")

        controller.refreshSuggestions()

        XCTAssertFalse(
            controller.suggestions.contains(where: \.isDefault),
            "a selection cannot be committed by space, so no candidate may be "
                + "marked default: \(controller.suggestions.map { ($0.text, $0.isDefault) })")
    }

    // MARK: Fix 5 — a stale refinement must not land over a selection

    /// **The measured defect.** A next-word request armed by a space on an
    /// empty prefix can still be in flight when a double tap selects a word;
    /// `refreshSuggestions` skips asking again but never cancelled the old
    /// request, and `applyRefinement`'s only staleness gate — `prefix ==
    /// currentWordPrefix` — is blind to a selection, since `currentWordPrefix`
    /// reads the same with or without one. The answer therefore landed over the
    /// selection's own correction candidates.
    func testAStaleRefinementDoesNotLandOverASelection() {
        let target = CursorTextTarget(before: "", selecting: "hello", after: " world")
        let controller = KeyboardController(target: target, language: .english)
        XCTAssertNotNil(controller.selection, "the fixture needs a live selection")

        let seeded = [
            Suggestion(text: "hello", language: .english),
            Suggestion(text: "hi", language: .english),
            Suggestion(text: "hey", language: .english)
        ]
        controller.suggestions = seeded

        // Simulates the refiner's answer arriving for the request armed before
        // the selection was made — `currentWordPrefix` still reads "" either way.
        controller.applyRefinement(["banana", "orange"], for: controller.currentWordPrefix)

        XCTAssertEqual(
            controller.suggestions, seeded,
            "an answer that arrives while a selection exists must not replace "
                + "the bar: \(controller.suggestions.map(\.text))")
    }
}
