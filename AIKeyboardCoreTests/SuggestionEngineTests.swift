import XCTest

@testable import AIKeyboardCore

/// `SuggestionEngine` is backed by `UITextChecker`, so these assert against
/// Apple's real dictionary rather than a table this repo controls. Every case
/// below was run once as a scratch probe against the Simulator before being
/// written down, per the standing rule: a claim about what an Apple API returns
/// needs to have actually been seen, not assumed.
@MainActor
final class SuggestionEngineTests: XCTestCase {

    // MARK: Completion of the word being typed

    func testEnglishPrefixCompletesToARealWord() {
        let results = SuggestionEngine.suggestions(
            prefix: "hel", context: "", languages: [.english])

        XCTAssertTrue(results.contains { $0.text.lowercased() == "hello" })
    }

    /// The literal keystrokes must always be a candidate, so the engine can
    /// never trap the user in a word they did not type.
    func testTheTypedPrefixIsAlwaysOffered() {
        let results = SuggestionEngine.suggestions(
            prefix: "xyzzy", context: "", languages: [.english])

        XCTAssertTrue(results.contains { $0.text == "xyzzy" })
    }

    /// `אנ` → `אני`, `אנחנו`, `אנשים`… — Hebrew word completion, verified against
    /// the Simulator before this was written. `UITextChecker` is not one of the
    /// three Apple stacks with no Hebrew; it has its own language list.
    func testHebrewPrefixCompletesToARealWord() {
        let results = SuggestionEngine.suggestions(
            prefix: "אנ", context: "", languages: [.hebrew])

        XCTAssertTrue(results.contains { $0.text == "אני" })
    }

    /// A prefix that is not the start of any dictionary word falls through to
    /// `guesses`, which corrects a misspelling rather than completing a word in
    /// progress. `recieve` completes to nothing (nothing starts with those six
    /// letters), which is what makes this case fall through rather than a
    /// prefix like `helo`, where `UITextChecker` has real completions
    /// (`helot`, `helots`) that crowd the correction out — a real, disclosed
    /// limit of a spell-checker with no frequency model behind it; see the
    /// note on `completions(for:typedLanguage:supplementary:)`.
    func testAMisspellingFallsBackToASpellingGuess() {
        let results = SuggestionEngine.suggestions(
            prefix: "recieve", context: "", languages: [.english])

        XCTAssertTrue(results.contains { $0.text.lowercased() == "receive" })
    }

    // MARK: Contractions

    /// `UITextChecker.guesses` cannot be trusted to fire on a two-letter
    /// prefix, so this is a real, hardcoded rule rather than a dictionary
    /// lookup — see the doc comment on `contractions`.
    func testMissingApostropheIsOfferedAtAnyLength() {
        let results = SuggestionEngine.suggestions(
            prefix: "im", context: "", languages: [.english])

        XCTAssertTrue(results.contains { $0.text == "I'm" })
    }

    func testDontExpandsToTheContraction() {
        let results = SuggestionEngine.suggestions(
            prefix: "dont", context: "I ", languages: [.english])

        XCTAssertTrue(results.contains { $0.text == "don't" })
    }

    // MARK: Supplementary lexicon

    /// Names from `UILexicon` outrank the system dictionary, because
    /// `UITextChecker` has never heard of them.
    func testSupplementaryWordsAreOfferedForAMatchingPrefix() {
        let results = SuggestionEngine.suggestions(
            prefix: "nit", context: "", languages: [.english],
            supplementary: ["Nitai"])

        XCTAssertTrue(results.contains { $0.text == "Nitai" })
    }

    func testSupplementaryWordsThatDoNotMatchThePrefixAreNotOffered() {
        let results = SuggestionEngine.suggestions(
            prefix: "hel", context: "", languages: [.english],
            supplementary: ["Nitai"])

        XCTAssertFalse(results.contains { $0.text == "Nitai" })
    }

    // MARK: Next word, nothing typed

    /// No public API predicts this; the table is small and disclosed. This
    /// pins the one behaviour the table promises rather than its contents,
    /// which are free to grow without breaking a test.
    func testNothingTypedOffersFollowOnWordsForARecognisedLastWord() {
        let results = SuggestionEngine.suggestions(
            prefix: "", context: "thanks ", languages: [.english])

        XCTAssertTrue(results.contains { $0.text == "for" })
    }

    func testNothingTypedAndNoContextOffersTheDefaults() {
        let results = SuggestionEngine.suggestions(
            prefix: "", context: "", languages: [.english])

        XCTAssertEqual(results.map(\.text), ["I", "The", "We"])
    }

    // MARK: Default candidate

    /// A short prefix is never overridden regardless of whether it is a real
    /// word — this is what stops autocorrect from turning `I` into `idea`.
    func testAShortPrefixIsNotMarkedForAutocorrect() {
        let results = SuggestionEngine.suggestions(
            prefix: "cat", context: "", languages: [.english])

        XCTAssertFalse(results.contains { $0.isDefault && $0.text.lowercased() != "cat" })
    }

    /// A real, `UITextChecker`-verified known word of four or more letters is
    /// also left alone — this is the case the four-letter gate exists to
    /// protect once length stops doing it automatically.
    func testAFourLetterKnownWordIsNotMarkedForAutocorrect() {
        let results = SuggestionEngine.suggestions(
            prefix: "chair", context: "", languages: [.english])

        XCTAssertFalse(results.contains { $0.isDefault && $0.text.lowercased() != "chair" })
    }

    /// A four-or-more-letter prefix `UITextChecker` does not recognise as a
    /// word is corrected — `sched` is not in the dictionary, and its top
    /// completion is `schedule`.
    func testAMisspelledFourLetterPrefixIsMarkedForAutocorrect() {
        let results = SuggestionEngine.suggestions(
            prefix: "sched", context: "", languages: [.english])

        XCTAssertTrue(results.contains { $0.isDefault && $0.text.lowercased() == "schedule" })
    }

    // MARK: Script detection (moved from MockSuggestionEngine, unchanged)

    func testDominantLanguageReadsHebrewOverLatin() {
        XCTAssertEqual(SuggestionEngine.dominantLanguage(in: "שלום שלום world"), .hebrew)
    }

    func testDominantLanguageReadsLatinOverHebrew() {
        XCTAssertEqual(SuggestionEngine.dominantLanguage(in: "hello world שלום"), .english)
    }

    func testDominantLanguageIsNilForDigitsAndPunctuationAlone() {
        XCTAssertNil(SuggestionEngine.dominantLanguage(in: "123 !?"))
    }
}
