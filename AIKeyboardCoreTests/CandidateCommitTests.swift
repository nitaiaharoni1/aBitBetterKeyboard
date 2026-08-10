import XCTest

@testable import AIKeyboardCore

/// Committing a candidate, which is the path that runs most: every space press
/// and every tap on the suggestion row.
///
/// **Nothing covered `replaceCurrentWord` at all**, and it carried the same two
/// defects `replaceTargetText` was rewritten to fix — a delete loop sized in
/// grapheme clusters, and no idea what a selection does to a backspace. The
/// corrections it mangles are this keyboard's own: `שלומ` → `שלום` is
/// `hebrewFinalFormCorrection`, written for Hebrew and pinned by
/// `SuggestionEngineTests`, and it fires on the space bar.
@MainActor
final class CandidateCommitTests: XCTestCase {

    private var autocorrect = true

    override func setUp() {
        super.setUp()
        autocorrect = SharedStore.shared.autocorrect
        SharedStore.shared.autocorrect = true
    }

    override func tearDown() {
        SharedStore.shared.autocorrect = autocorrect
        super.tearDown()
    }

    /// One case, twice: against the model and against a real `UITextView`.
    private func check(
        before: String,
        selecting: String = "",
        after: String = "",
        candidate: String,
        bySpace expectedBySpace: String,
        byTap expectedByTap: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for byTap in [false, true] {
            let mock = CursorTextTarget(
                before: before, selecting: selecting.isEmpty ? nil : selecting, after: after)
            let live = LiveTextViewTarget(before: before, selecting: selecting, after: after)
            let expected = byTap ? expectedByTap : expectedBySpace

            for (target, document, name) in [
                (mock as TextTarget, { mock.document }, "the model"),
                (live as TextTarget, { live.document }, "a real UITextView")
            ] {
                let controller = KeyboardController(target: target)
                let suggestion = Suggestion(text: candidate, language: .english, isDefault: true)
                controller.suggestions = [suggestion]
                if byTap {
                    controller.apply(suggestion)
                } else {
                    controller.press(.space)
                }
                XCTAssertEqual(
                    document(), expected,
                    "\(byTap ? "tap" : "space") against \(name)", file: file, line: line)
            }
        }
    }

    /// **The measured failure, row one.** `שָׁ` is one grapheme cluster and three
    /// presses, so a loop sized `prefix.count` stops one mark short and leaves the
    /// half-deleted letter in front of the candidate: `hi שָשָׁלום`.
    func testHebrewWithNiqqudCommitsWholeCharacters() {
        check(
            before: "hi שָׁלומ", candidate: "שָׁלום",
            bySpace: "hi שָׁלום ", byTap: "hi שָׁלום ")
    }

    /// Arabic: `مُ` is two presses and `مَّ` is three.
    func testArabicHarakatCommitWholeCharacters() {
        check(
            before: "hi مُحَمَّد", candidate: "محمد",
            bySpace: "hi محمد ", byTap: "hi محمد ")
    }

    /// Devanagari: `क्षि` is four presses.
    func testDevanagariConjunctsCommitWholeCharacters() {
        check(
            before: "hi क्षिति", candidate: "क्षति",
            bySpace: "hi क्षति ", byTap: "hi क्षति ")
    }

    /// An emoji in the partial word goes in one press, so a loop sized in UTF-16
    /// would over-delete exactly where the cluster loop under-deletes.
    func testAnEmojiInThePartialWord() {
        check(
            before: "ok 🎉par", candidate: "party",
            bySpace: "ok party ", byTap: "ok party ")
    }

    /// **A live selection, which is the other half of the same bug.** The first
    /// backspace removes the selection and every press after it ate real text:
    /// `hello wor⟦ld mo⟧re` came back `hello wword re`, with the user's `or` gone.
    ///
    /// The rule now is the one typing already follows — replace the selection,
    /// touch nothing outside it. On the space bar that means the space replaces
    /// the selection and no candidate is committed, exactly as on the system
    /// keyboard; on a tap it means the candidate is typed over the selection and
    /// the partial word in front of it is left alone, because with a range
    /// selected there is no word under the cursor.
    func testASelectionIsReplacedAndNothingAroundItIs() {
        check(
            before: "hello wor", selecting: "ld mo", after: "re", candidate: "word",
            bySpace: "hello wor re", byTap: "hello worword re")
    }
}
