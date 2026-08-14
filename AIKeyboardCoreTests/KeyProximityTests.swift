import XCTest

@testable import AIKeyboardCore

@MainActor
final class KeyProximityTests: XCTestCase {

    func testRowsMatchTheLetterLayouts() {
        XCTAssertEqual(
            KeyProximity.rows(for: .english),
            KeyboardLayout.letterLayouts[.english]!.rows.map { $0.joined() })
        XCTAssertEqual(KeyProximity.rows(for: .hebrew), KeyboardLayout.hebrewRows)
        XCTAssertEqual(
            KeyProximity.rows(for: .hebrew),
            KeyboardLayout.letterLayouts[.hebrew]!.rows.map { $0.joined() })
    }

    func testEnglishAdjacency() {
        XCTAssertTrue(KeyProximity.areAdjacent("q", "w", in: .english))
        XCTAssertTrue(KeyProximity.areAdjacent("Q", "w", in: .english))
        XCTAssertFalse(KeyProximity.areAdjacent("q", "p", in: .english))
        XCTAssertTrue(KeyProximity.areAdjacent("e", "d", in: .english))
        XCTAssertFalse(KeyProximity.areAdjacent("a", "l", in: .english))
    }

    func testHebrewAdjacency() {
        XCTAssertTrue(KeyProximity.areAdjacent("ק", "ר", in: .hebrew))
    }

    func testAdjacentNeighbourOutranksAWorseOrdinal() {
        let adjacent = SuggestionEngine.Candidate(
            text: "zzadj", language: .english, source: .neighbour, ordinal: 4,
            keyAdjacent: true)
        let farther = SuggestionEngine.Candidate(
            text: "zzfar", language: .english, source: .neighbour, ordinal: 0,
            keyAdjacent: false)
        XCTAssertGreaterThan(
            SuggestionEngine.score(adjacent), SuggestionEngine.score(farther),
            "50 has to beat ordinal*8 inside the neighbour tier")
    }

    func testASameLengthNonTranspositionNeighbourStillDoesNotCommit() {
        XCTAssertFalse(SeedLanguageModel.isTransposition("נכון", of: "מכונ"))
        let results = SuggestionEngine.suggestions(
            prefix: "מכונ", context: "", languages: [.hebrew],
            personal: PersonalLanguageModel(url: nil))
        XCTAssertNotEqual(
            results.first(where: \.isDefault)?.text, "נכון",
            "key proximity must not start committing substitutions: \(results.map(\.text))")
    }

    func testATranspositionIsNotAnAdjacentSubstitution() {
        XCTAssertTrue(SeedLanguageModel.isTransposition("the", of: "teh"))
        XCTAssertFalse(KeyProximity.isAdjacentSubstitution("teh", "the", in: .english))
    }
}
