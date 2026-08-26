import XCTest

@testable import AIKeyboardCore

/// Clitic-aware Hebrew personalization. The store stays exact. Ranking and
/// inherited followers read a derived index.
///
/// Each assertion is the answer the exact-only build produced for the same
/// input. Shared ranking returned 2, protection of the stem returned true once
/// `rankingCount` leaked into `isProtected`, and inherited followers returned
/// an empty list.
@MainActor
final class HebrewPersonalizationTests: XCTestCase {

    private func model() -> PersonalLanguageModel {
        PersonalLanguageModel(url: nil)
    }

    private func record(
        _ word: String, previous: String? = nil, times: Int,
        on personal: PersonalLanguageModel
    ) {
        for _ in 0..<times {
            personal.record(word: word, previous: previous, language: .hebrew, permitted: true)
        }
    }

    /// `עבודה` is in the seed list, so `לעבודה` and `בעבודה` share one stem
    /// without ever storing the bare noun. The exact-only `count` of the noun
    /// stayed 0 and ranking followed it.
    func testRelatedSurfacesShareRankingWithoutMergingExactCounts() {
        let personal = model()
        record("לעבודה", times: 2, on: personal)
        record("בעבודה", times: 2, on: personal)

        XCTAssertEqual(personal.count(of: "עבודה", in: .hebrew), 0)
        XCTAssertEqual(personal.count(of: "לעבודה", in: .hebrew), 2)
        XCTAssertEqual(personal.count(of: "בעבודה", in: .hebrew), 2)
        XCTAssertEqual(
            personal.rankingCount(of: "עבודה", in: .hebrew), 4,
            "exact-only ranking saw 0 for the unstored stem")
        XCTAssertEqual(personal.rankingCount(of: "לעבודה", in: .hebrew), 4)
        XCTAssertEqual(personal.rankingCount(of: "בעבודה", in: .hebrew), 4)
        XCTAssertEqual(
            Set(personal.learnedWords().map(\.word)), ["בעבודה", "לעבודה"],
            "dictionary display merged related surfaces")
        XCTAssertEqual(
            personal.learnedWords().map(\.count).sorted(), [2, 2],
            "exact counts were rewritten")
    }

    /// Three sightings of the glued form must not protect the stem. The
    /// leaked-ranking build answered true for `עבודה`.
    func testProtectionStaysExact() {
        let personal = model()
        record("לעבודה", times: 3, on: personal)

        XCTAssertTrue(personal.isProtected("לעבודה", in: .hebrew))
        XCTAssertFalse(
            personal.isProtected("עבודה", in: .hebrew),
            "protection followed rankingCount and locked the untyped stem")
        XCTAssertFalse(personal.isProtected("בעבודה", in: .hebrew))
        XCTAssertEqual(personal.count(of: "עבודה", in: .hebrew), 0)
        XCTAssertEqual(personal.rankingCount(of: "עבודה", in: .hebrew), 3)
    }

    /// Followers of `עבודה` must appear after `לעבודה`. The exact-previous
    /// build returned []. Spellings stay stored surfaces.
    func testFollowersAreInheritedAcrossRelatedSurfaces() {
        let personal = model()
        record("עבודה", times: 2, on: personal)
        record("קשה", previous: "עבודה", times: 2, on: personal)
        record("לעבודה", times: 2, on: personal)
        record("מחר", previous: "לעבודה", times: 2, on: personal)

        XCTAssertEqual(
            personal.followers(after: "עבודה", in: .hebrew, limit: 3), ["קשה", "מחר"],
            "exact-only lookup returned [קשה] and dropped the sibling pair")
        XCTAssertEqual(
            personal.followers(after: "לעבודה", in: .hebrew, limit: 3), ["מחר", "קשה"],
            "exact-only lookup returned [מחר] and dropped the inherited pair")
        XCTAssertEqual(
            personal.followers(after: "בעבודה", in: .hebrew, limit: 3), ["מחר", "קשה"],
            "no inherited followers: \(personal.followers(after: "בעבודה", in: .hebrew, limit: 3))")
        XCTAssertEqual(personal.followers(after: "אני", in: .hebrew, limit: 3), [])
    }

    /// A pair stored as `אני` → `עבודה` must not invent `לעבודה`.
    func testFollowersNeverGlueACliticOntoAStem() {
        let personal = model()
        record("עבודה", previous: "אני", times: 2, on: personal)

        XCTAssertEqual(personal.followers(after: "אני", in: .hebrew, limit: 3), ["עבודה"])
        XCTAssertFalse(
            personal.followers(after: "אני", in: .hebrew, limit: 3).contains("לעבודה"),
            "the follower list manufactured a glued form")
    }

    /// An unvouched stem must not pool unrelated glued guesses.
    func testUnvouchedStemsDoNotShareRanking() {
        let personal = model()
        record("לזקבמ", times: 2, on: personal)
        record("בזקבמ", times: 2, on: personal)

        XCTAssertEqual(personal.count(of: "לזקבמ", in: .hebrew), 2)
        XCTAssertEqual(personal.rankingCount(of: "לזקבמ", in: .hebrew), 2)
        XCTAssertEqual(personal.rankingCount(of: "בזקבמ", in: .hebrew), 2)
        XCTAssertEqual(personal.rankingCount(of: "זקבמ", in: .hebrew), 0)
    }

    func testEnglishRankingCountStaysExact() {
        let personal = model()
        personal.record(word: "hello", previous: nil, language: .english, permitted: true)
        personal.record(word: "hello", previous: nil, language: .english, permitted: true)
        XCTAssertEqual(personal.count(of: "hello", in: .english), 2)
        XCTAssertEqual(personal.rankingCount(of: "hello", in: .english), 2)
    }

    /// Candidate ranking is the stamp, not `count(of:)`. The old stamp put 2
    /// on `לעבודה` after two sightings of `בעבודה` and two of itself.
    func testCandidateRankingUsesHebrewRankingCount() {
        let personal = model()
        record("לעבודה", times: 2, on: personal)
        record("בעבודה", times: 2, on: personal)

        var candidates = [
            SuggestionEngine.Candidate(text: "לעבודה", language: .hebrew, source: .checker)
        ]
        SuggestionEngine.stampPersonalCounts(&candidates, personal: personal)
        XCTAssertEqual(
            candidates[0].personalCount, 4,
            "the stamp still wrote the exact count: \(candidates[0].personalCount)")
    }

    func testEnglishRecordPruneAndForgetKeepTheHebrewIndexCached() {
        let personal = model()
        record("לעבודה", times: 2, on: personal)
        XCTAssertEqual(personal.rankingCount(of: "עבודה", in: .hebrew), 2)
        XCTAssertTrue(personal.hasCachedHebrewIndex)

        personal.record(word: "hello", previous: nil, language: .english, permitted: true)
        XCTAssertTrue(personal.hasCachedHebrewIndex)

        for index in 0...4000 {
            personal.record(
                word: englishWord(index), previous: nil, language: .english, permitted: true)
        }
        XCTAssertTrue(personal.hasCachedHebrewIndex, "pruning English discarded the Hebrew cache")

        personal.record(word: "forgettable", previous: nil, language: .english, permitted: true)
        personal.forget("forgettable", in: .english)
        XCTAssertTrue(personal.hasCachedHebrewIndex)
    }

    func testEnglishOnlyReloadKeepsTheHebrewIndexCached() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("hebrew-index-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let writer = PersonalLanguageModel(url: url)
        record("לעבודה", times: 2, on: writer)
        writer.record(word: "hello", previous: nil, language: .english, permitted: true)
        writer.save()

        let reader = PersonalLanguageModel(url: url)
        XCTAssertEqual(reader.rankingCount(of: "עבודה", in: .hebrew), 2)
        XCTAssertTrue(reader.hasCachedHebrewIndex)

        writer.record(word: "world", previous: nil, language: .english, permitted: true)
        writer.save()
        reader.reload()

        XCTAssertEqual(reader.count(of: "world", in: .english), 1)
        XCTAssertTrue(reader.hasCachedHebrewIndex, "an English-only reload discarded the Hebrew cache")
    }

    private func englishWord(_ index: Int) -> String {
        var value = index
        var suffix = ""
        repeat {
            suffix.append(Character(UnicodeScalar(97 + value % 26)!))
            value /= 26
        } while value > 0
        return "cacheword" + suffix
    }
}
