import XCTest

@testable import AIKeyboardCore

@MainActor
final class AutocorrectAmbiguityTests: XCTestCase {
    func testARejectedWrongLayoutCorrectionUsesTheReplacementLanguage() {
        let typed = SuggestionEngine.Candidate(text: "akuo,", language: .english, source: .typed)
        let correction = SuggestionEngine.Candidate(text: "שלום,", language: .hebrew, source: .layout)
        let personal = PersonalLanguageModel(url: nil)
        XCTAssertEqual(
            SuggestionEngine.commitReason(
                typed.text, previousWords: [], typedLanguage: .english,
                results: [typed, correction], supplementary: [], personal: personal), .wrongLayout)

        personal.recordRejectedCorrection(
            original: "akuo", replacement: "שלום", language: .hebrew, permitted: true)

        XCTAssertNil(
            SuggestionEngine.commitReason(
                typed.text, previousWords: [], typedLanguage: .english,
                results: [typed, correction], supplementary: [], personal: personal))
    }

    func testRealWordsAreNotReplacedByAmbiguousContractions() {
        for (word, context) in [
            ("its", "The dog hurt "), ("ill", "I feel "), ("lets", "She "),
            ("cant", "He spoke in "), ("wont", "As was his ")
        ] {
            for level in [AutocorrectLevel.confident, .full] {
                let results = SuggestionEngine.suggestions(
                    prefix: word, context: context, languages: [.english],
                    personal: PersonalLanguageModel(url: nil), autocorrect: level)
                XCTAssertEqual(results.first(where: \.isDefault)?.text, word, "\(context)\(word)")
            }
        }
    }

    func testAnAmbiguousContractionIsStillOfferedForATap() {
        let results = SuggestionEngine.generatedCompletions(
            for: "ill", previousWords: [], context: "", typedLanguage: .english,
            otherLanguage: nil, supplementary: [], personal: PersonalLanguageModel(url: nil))
        XCTAssertTrue(results.contains { $0.text == "I'll" })
        XCTAssertFalse(results.contains { $0.text == "I'll" && $0.source == .orthography })
    }

    func testUnambiguousContractionsStillCorrectAutomatically() {
        let results = SuggestionEngine.suggestions(
            prefix: "dont", context: "I ", languages: [.english],
            personal: PersonalLanguageModel(url: nil), autocorrect: .confident)
        XCTAssertEqual(results.first(where: \.isDefault)?.text, "don't")
    }

    func testEquallyPlausibleHebrewCorrectionsKeepTheTypedWord() {
        let typed = SuggestionEngine.Candidate(text: "מהעבדה", language: .hebrew, source: .typed)
        let first = SuggestionEngine.Candidate(text: "מהעובדה", language: .hebrew, source: .frequency)
        let other = SuggestionEngine.Candidate(text: "מהעבודה", language: .hebrew, source: .frequency)
        XCTAssertTrue(
            SuggestionEngine.correctionIsAmbiguous(
                typed: typed.text, winner: first, alternatives: [typed, first, other]))
        XCTAssertNil(
            SuggestionEngine.commitReason(
                typed.text, previousWords: [], typedLanguage: .hebrew,
                results: [typed, first], supplementary: [], personal: PersonalLanguageModel(url: nil),
                alternatives: [typed, first, other]))
    }

    func testContextMustDistinguishTheWinnerFromItsCompetitor() {
        var first = SuggestionEngine.Candidate(
            text: "מהעובדה", language: .hebrew, source: .frequency, followsImmediateContext: true)
        var other = SuggestionEngine.Candidate(
            text: "מהעבודה", language: .hebrew, source: .frequency)
        XCTAssertFalse(
            SuggestionEngine.correctionIsAmbiguous(
                typed: "מהעבדה", winner: first, alternatives: [first, other]))
        other.followsImmediateContext = true
        XCTAssertTrue(
            SuggestionEngine.correctionIsAmbiguous(
                typed: "מהעבדה", winner: first, alternatives: [first, other]))
        first.followsImmediateContext = false
        XCTAssertTrue(
            SuggestionEngine.correctionIsAmbiguous(
                typed: "מהעבדה", winner: first, alternatives: [first, other]))
    }

    func testDistantContextDoesNotResolveACorrectionTie() {
        let first = SuggestionEngine.Candidate(
            text: "מהעובדה", language: .hebrew, source: .frequency, followsContext: true)
        let other = SuggestionEngine.Candidate(
            text: "מהעבודה", language: .hebrew, source: .frequency)
        XCTAssertTrue(
            SuggestionEngine.correctionIsAmbiguous(
                typed: "מהעבדה", winner: first, alternatives: [first, other]))
    }

    func testARepeatedSurfaceAndADistantAlternativeDoNotCreateAmbiguity() {
        let first = SuggestionEngine.Candidate(text: "hello", language: .english, source: .neighbour)
        let duplicate = SuggestionEngine.Candidate(text: "Hello", language: .english, source: .frequency)
        let other = SuggestionEngine.Candidate(text: "hero", language: .english, source: .correction)
        XCTAssertFalse(
            SuggestionEngine.correctionIsAmbiguous(
                typed: "helo", winner: first, alternatives: [first, duplicate, other]))
    }

    func testTwoCommonEquallyCheapSlipsRemainAmbiguousWithoutContext() {
        let first = SuggestionEngine.Candidate(text: "hello", language: .english, source: .neighbour)
        let other = SuggestionEngine.Candidate(text: "help", language: .english, source: .neighbour)
        XCTAssertTrue(
            SuggestionEngine.correctionIsAmbiguous(
                typed: "helo", winner: first, alternatives: [first, other]))
    }

    func testAPersonalCompletionCannotHideItsUnshownCompetitor() {
        let typed = SuggestionEngine.Candidate(text: "keyb", language: .english, source: .typed)
        let first = SuggestionEngine.Candidate(text: "KeyboardKit", language: .english, source: .personal)
        let other = SuggestionEngine.Candidate(text: "keyboard", language: .english, source: .seed)
        XCTAssertNil(
            SuggestionEngine.commitReason(
                typed.text, previousWords: [], typedLanguage: .english,
                results: [typed, first], supplementary: ["KeyboardKit"],
                personal: PersonalLanguageModel(url: nil), alternatives: [typed, first, other]))
    }

    func testContextRankingCanSeeSeedCandidatesBeyondTheDrawnSlots() {
        let expected = SeedLanguageModel.words(startingWith: "s", in: .english, limit: 12)
        XCTAssertGreaterThan(expected.count, 3)
        let generated = SuggestionEngine.generatedCompletions(
            for: "s", previousWords: [], context: "", typedLanguage: .english,
            otherLanguage: nil, supplementary: [], personal: PersonalLanguageModel(url: nil))
        for word in expected.dropFirst(3) {
            XCTAssertTrue(
                generated.contains { $0.text == word && $0.source == .seed },
                "\(word) was discarded before context ranking")
        }
    }
}
