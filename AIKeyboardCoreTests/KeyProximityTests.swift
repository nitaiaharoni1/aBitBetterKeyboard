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

    /// **Load-bearing.** Row 0 (8 keys) index 1 and row 1 (10 keys) index 0
    /// share a raw column index, which the old `colGap <= 1` test called
    /// adjacent. The rendered keyboard puts them 1.51 key widths apart —
    /// over a full key width — because row 0 sits to the *right* of its own
    /// index (delete pins its far end, so nothing centres the row on it).
    /// Fails against the old index-only build.
    func testReshAndShinShareARawColumnIndexButAreNotPhysicallyAdjacent() {
        XCTAssertFalse(
            KeyProximity.areAdjacent("ר", "ש", in: .hebrew),
            "resh and shin share a raw column index but sit over a key width apart")
    }

    /// **Load-bearing, the mirror-image drop.** Row 1 (10 keys) index 0 and
    /// row 2 (9 keys) index 1 share a raw column index the old test called
    /// adjacent; row 2 sits to the *right* of row 1 by almost half a key, so
    /// the geometry puts them over a key width apart in the other direction.
    /// Fails against the old index-only build.
    func testShinAndSamekhShareARawColumnIndexButAreNotPhysicallyAdjacent() {
        XCTAssertFalse(
            KeyProximity.areAdjacent("ש", "ס", in: .hebrew),
            "shin and samekh share a raw column index but sit over a key width apart")
    }

    /// Team lead's suspicion pair, resolved: pe (last of the 8-key top row)
    /// is within a key width of final-kaf in the row below and stays
    /// adjacent — both the old and the new test agree here, so this pins
    /// behaviour rather than catching the bug.
    func testPeAndFinalKafStayAdjacentAcrossTheUnevenRows() {
        XCTAssertTrue(KeyProximity.areAdjacent("פ", "ך", in: .hebrew))
    }

    /// pe against final-pe, one column further along the row below: two
    /// columns apart under the old raw-index test and over two key widths
    /// apart under the geometry. Unchanged; pins the boundary next to the
    /// pair above.
    func testPeAndFinalPeStayNotAdjacentAcrossTheUnevenRows() {
        XCTAssertFalse(KeyProximity.areAdjacent("פ", "ף", in: .hebrew))
    }

    /// final-mem against final-kaf: two raw columns apart under the old test
    /// and over two key widths apart under the geometry. Unchanged; pins the
    /// other pair the team lead asked to check.
    func testFinalMemAndFinalKafStayNotAdjacentAcrossTheUnevenRows() {
        XCTAssertFalse(KeyProximity.areAdjacent("ם", "ך", in: .hebrew))
    }

    /// Same-row adjacency is an exact index test, untouched by the geometry
    /// fix. alef and tet are consecutive letters of the top row and are the
    /// pair behind a real user report of one substituting for the other in a
    /// word; this must stay true whatever else moves.
    func testAlefAndTetStayAdjacentInTheSameRow() {
        XCTAssertTrue(KeyProximity.areAdjacent("א", "ט", in: .hebrew))
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
