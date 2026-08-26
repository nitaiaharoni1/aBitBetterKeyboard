import XCTest

@testable import AIKeyboardCore

@MainActor
final class ConversationalHebrewIntegrationTests: XCTestCase {
    private func emptyPersonal() -> PersonalLanguageModel {
        PersonalLanguageModel(url: nil)
    }

    func testEmptyPrefixUsesCorpusFollowersOnlyWhenTheSeedIsSilent() {
        let context = "ראש הממשלה "
        let sentence = SuggestionEngine.previousWords(in: context, limit: .max)
        XCTAssertTrue(
            SeedLanguageModel.followers(mentionedIn: sentence, in: .hebrew).isEmpty)

        let trace = SuggestionEngine.nextWordTrace(
            context: context, contextLanguage: .hebrew, personal: emptyPersonal())
        XCTAssertTrue(
            trace.generated.contains {
                $0.source == .conversational && $0.text == "בנימין"
            })
        let evaluation = SuggestionEngine.evaluate(
            prefix: "", context: context, languages: [.hebrew], personal: emptyPersonal())
        XCTAssertTrue(evaluation.visible.contains("בנימין"))

        let seededContext = "אני "
        let seededSentence = SuggestionEngine.previousWords(in: seededContext, limit: .max)
        XCTAssertFalse(
            SeedLanguageModel.followers(mentionedIn: seededSentence, in: .hebrew).isEmpty)
        let seededTrace = SuggestionEngine.nextWordTrace(
            context: seededContext, contextLanguage: .hebrew, personal: emptyPersonal())
        XCTAssertFalse(seededTrace.generated.contains { $0.source == .conversational })
    }

    func testPersonalFollowerStillLeadsTheCorpusFallback() {
        let personal = emptyPersonal()
        personal.record(
            word: "דנה", previous: "הממשלה", language: .hebrew, permitted: true)
        personal.record(
            word: "דנה", previous: "הממשלה", language: .hebrew, permitted: true)

        let evaluation = SuggestionEngine.evaluate(
            prefix: "", context: "ראש הממשלה ", languages: [.hebrew], personal: personal)

        XCTAssertEqual(evaluation.ranked.first(where: \.isDefault)?.text, "דנה")
        XCTAssertTrue(evaluation.visible.contains("בנימין"))
    }

    func testConversationalSourceSitsBetweenCheckerAndNeighbour() {
        XCTAssertLessThan(
            SuggestionEngine.Source.checker, SuggestionEngine.Source.conversational)
        XCTAssertLessThan(
            SuggestionEngine.Source.conversational, SuggestionEngine.Source.neighbour)
        XCTAssertLessThan(
            SuggestionEngine.Source.conversational, SuggestionEngine.Source.seed)
    }
}
