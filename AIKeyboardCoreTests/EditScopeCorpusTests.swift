import XCTest

@testable import AIKeyboardCore

/// Corpus-table tests extracted from `EditScopeTests`.
final class EditScopeCorpusTests: XCTestCase {

    // MARK: The corpus, as a table

    /// Every Fix entry in `Bar/ai-text`, as `(what the user typed, what a good
    /// writer produces, the corrections that names)`. Applying the scope check to
    /// a reference answer has to give that answer back: if it does not, the rule
    /// is undoing a correction the product is measured on.
    func testTheScopeCheckNeverUndoesACorrectionTheReferenceAnswersMake() {
        let corpus = editScopeCorpus
        for (source, reference, corrections) in corpus {
            XCTAssertEqual(
                EditScope.applied(reference, to: source, corrections: corrections),
                reference,
                "the scope check changed the reference answer for \(source.debugDescription)"
            )
        }
    }
}
