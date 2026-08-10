import Foundation
import XCTest

@testable import AIKeyboardCore
@testable import AIKeyboardShared

/// Holds the shipping transcription prompt to the one the bar was scored with.
///
/// **There are two copies of this prompt and there is no way to have one.** The
/// product's is Swift, in `DictationPrompt`; the scoring harness is Python, in
/// `Bar/dictation/harness/transcribe.py`. The screen-context bar carries the
/// identical duplication for the identical reason. What can be prevented is the
/// two *drifting*, which is what this file does: it reads the Python source off
/// the repository and compares the strings.
///
/// Compared with whitespace collapsed, because one side wraps with Swift's `\`
/// line continuations and the other with Python's, and a difference in wrapping
/// is not a difference in prompt. Anything else — a reordered field, a dropped
/// rule, a softened example — fails here.
final class DictationPromptTests: XCTestCase {

    private static let harness = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Bar/dictation/harness/transcribe.py")

    private func python(_ name: String) throws -> String {
        let source = try String(contentsOf: Self.harness, encoding: .utf8)
        // `NAME = """…"""`, with Python's backslash continuations resolved the
        // way Python resolves them.
        guard let start = source.range(of: "\(name) = \"\"\""),
            let end = source.range(of: "\"\"\"", range: start.upperBound..<source.endIndex)
        else {
            XCTFail("\(name) is no longer a triple-quoted string in transcribe.py")
            return ""
        }
        return String(source[start.upperBound..<end.lowerBound])
            .replacingOccurrences(of: "\\\n", with: "")
    }

    private func collapsed(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    func testTheInstructionsMatchTheHarness() throws {
        XCTAssertEqual(
            collapsed(DictationPrompt.instructions), collapsed(try python("INSTRUCTIONS")))
    }

    func testTheTaskMatchesTheHarness() throws {
        XCTAssertEqual(collapsed(DictationPrompt.task), collapsed(try python("TASK")))
    }

    /// Worth 3.5 points of word error rate and nine named entities on its own
    /// (`Bar/dictation/ablation/loanwords.json`). The examples are the working
    /// part, so an edit that keeps the rule and drops them fails here.
    func testTheLoanwordRuleMatchesTheHarness() throws {
        XCTAssertEqual(collapsed(DictationPrompt.loanwords), collapsed(try python("LOANWORDS")))
        for example in ["פייבור", "אונבורדינג", "סאמרי"] {
            XCTAssertTrue(
                DictationPrompt.loanwords.contains(example),
                "the transliteration example \(example) was removed")
        }
    }

    /// The harness hardcodes Hebrew and English, because that is what the corpus
    /// speaks; the product builds the same sentence from the user's own enabled
    /// keyboards, which is what makes it work for the other 62 languages.
    func testTheLanguageHintIsTheHarnessSentenceBuiltFromTheUsersKeyboards() throws {
        let built = DictationPrompt.languageHint([.hebrew, .english])
        XCTAssertEqual(collapsed(built), collapsed(try python("HINT")))
    }

    func testTheHintListsThreeOrMoreLanguagesReadably() {
        let hint = DictationPrompt.languageHint([.hebrew, .english, .russian])
        XCTAssertTrue(hint.contains("Hebrew, English and Russian"), hint)
    }

    /// No keyboards, no sentence. An empty list must not produce "these
    /// keyboards: ." — which would be a instruction to expect nothing at all.
    func testNoLanguagesMeansNoHint() {
        XCTAssertEqual(DictationPrompt.languageHint([]), "")
        XCTAssertEqual(DictationPrompt.prompt(for: []), DictationPrompt.task + DictationPrompt.loanwords)
    }

    /// **Order is load-bearing and is the reason these are a list rather than a
    /// dictionary.** The model fills fields as it emits them: `speech` is settled
    /// before any text exists, and `languages` before the transcript, which is
    /// the split worth eight points on the screen-context bar and is what keeps
    /// English words out of Hebrew letters here.
    func testTheFieldsAreInTheMeasuredOrder() {
        XCTAssertEqual(DictationPrompt.fields.map(\.name), ["speech", "languages", "text"])
    }

    /// The whole request, assembled the way `CloudDictation.transcribe` does it.
    func testTheAssembledPromptIsTaskThenHintThenLoanwords() {
        let prompt = DictationPrompt.prompt(for: [.hebrew, .english])
        let hint = try? XCTUnwrap(prompt.range(of: "types on these keyboards"))
        let loanwords = try? XCTUnwrap(prompt.range(of: "still an English word"))
        XCTAssertNotNil(hint)
        XCTAssertNotNil(loanwords)
        if let hint, let loanwords {
            XCTAssertTrue(hint.lowerBound < loanwords.lowerBound)
        }
        XCTAssertTrue(prompt.hasPrefix(DictationPrompt.task))
    }
}
