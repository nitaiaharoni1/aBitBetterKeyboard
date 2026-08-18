import XCTest

@testable import AIKeyboardCore

/// What the keyboard gives back when iOS says it is short of memory.
///
/// **The build before this held every word list for the life of the process and
/// answered `didReceiveMemoryWarning` by writing one number into a file.** That
/// warning is the only notice iOS sends before it kills a keyboard extension, and
/// a killed extension is replaced by the stock keyboard with no crash log, no
/// signal and no callback — see `KeyboardMemoryPeak` and NIT-126. So the fix is
/// to release the lists, and the thing that has to be true of every release is
/// that it costs nothing but time.
///
/// Each assertion below rejects a cache that is *not* rebuildable: one holding
/// something it cannot read out of the bundle again, or a purge that empties the
/// wrong store and leaves the next lookup answering with silence. A test that
/// only called `dropRebuildableCaches()` and checked for no crash would pass
/// against a keyboard whose spell-checking had gone dead.
@MainActor
final class RebuildableCachesTests: XCTestCase {

    /// The end-to-end shape: the answer a user sees is identical either side of a
    /// purge. `restored` is `MissingSpaces` on top of `GroupedLexiconResource`, so
    /// this covers both of those caches through the surface that uses them.
    func testFixStillSplitsJammedTextAfterThePurge() {
        let before = MissingSpaces.restored("מהאופישלומהקורה")
        XCTAssertEqual(before, "מה אופי שלו מה קורה", "the corpus case moved")

        KeyboardController.dropRebuildableCaches()

        XCTAssertEqual(
            MissingSpaces.restored("מהאופישלומהקורה"), before,
            "Fix stopped splitting jammed Hebrew once the lists were given back")
        XCTAssertEqual(
            MissingSpaces.restored("hellothere"), "hello there",
            "Fix stopped splitting jammed English once the lists were given back")
    }

    /// The typo corrector's own block, which is the largest of the three and the
    /// one a language switch builds. `rank` and `isWord` read different halves of
    /// it, so a purge that rebuilt only part would show here.
    func testTheTypoLexiconAnswersTheSameAfterThePurge() {
        for language in [KeyboardLanguage.english, .hebrew] {
            let word = language == .english ? "the" : "עבודה"
            let rank = TypoLexicon.rank(of: word, in: language)
            XCTAssertNotNil(rank, "\(word) is not in the bundled list at all")
            XCTAssertTrue(TypoLexicon.isWord(word, in: language))

            KeyboardController.dropRebuildableCaches()

            XCTAssertEqual(
                TypoLexicon.rank(of: word, in: language), rank,
                "\(word) changed rank across a purge, so the block was not rebuilt")
            XCTAssertTrue(
                TypoLexicon.isWord(word, in: language),
                "\(word) stopped being a word across a purge")
        }
    }

    /// The grouped decoder's list, which is the one cache that exists to be held.
    /// Purging it must cost a re-read and nothing else.
    func testTheGroupedListIsWholeAgainAfterThePurge() {
        let count = GroupedLexiconResource.words(for: .hebrew).count
        XCTAssertGreaterThan(count, 1000, "the bundled Hebrew list did not load at all")

        KeyboardController.dropRebuildableCaches()

        XCTAssertEqual(
            GroupedLexiconResource.words(for: .hebrew).count, count,
            "the list came back short, so the purge dropped more than a cache")
    }
}
