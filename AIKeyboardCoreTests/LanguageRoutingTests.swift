import XCTest

@testable import AIKeyboardCore

/// Routing is the part of this feature that can be tested without a model, and
/// it is also the part most likely to be wrong: Apple's on-device model does not
/// support Hebrew, so anything that reaches it in Hebrew comes back translated.
final class LanguageDetectorTests: XCTestCase {

    func testEnglishIsLatinOnly() {
        XCTAssertEqual(LanguageDetector.scripts(in: "Can you send me the ID?"), [.latin])
    }

    func testHebrewIsHebrewOnly() {
        XCTAssertEqual(LanguageDetector.scripts(in: "אני אבדוק את זה"), [.hebrew])
    }

    /// The trap this router exists for. Four fifths of these characters are
    /// Latin, so anything that picks a single dominant language sends it to the
    /// English-only path and never sees the Hebrew typo at the end.
    func testMostlyLatinSentenceStillReportsHebrew() {
        let mixed = "Can you check the deployment on staging, אני חושב שיש שם באג בבקשא"
        XCTAssertEqual(LanguageDetector.scripts(in: mixed), [.latin, .hebrew])
    }

    func testLoanwordsInHebrewReportBothScripts() {
        XCTAssertEqual(
            LanguageDetector.scripts(in: "אני אשלח לך את ה-document מחר אחרי ה-standup"),
            [.latin, .hebrew]
        )
    }

    /// Digits, punctuation and emoji are not evidence of a language, so a
    /// message made only of them must not be routed away from the on-device model.
    func testNonLettersAreIgnored() {
        XCTAssertEqual(LanguageDetector.scripts(in: "123 — !? 😅"), [])
    }

    func testUnknownScriptIsReportedAsOther() {
        XCTAssertTrue(LanguageDetector.scripts(in: "привет").contains(.other))
    }
}

// MARK: - Prompt selection

final class PromptSelectionTests: XCTestCase {

    /// A prompt carrying Hebrew examples translated every English test input
    /// into Hebrew when this was measured against the real model, so the two
    /// sets must never be merged and must be picked by the text, not the layout.
    func testEnglishAndHebrewPromptsAreDistinct() {
        XCTAssertNotEqual(Prompts.fix(for: "teh meeting"), Prompts.fix(for: "אני יבדוק"))
    }

    func testAnyHebrewSelectsTheHebrewPrompt() {
        let mixed = "Can you check the deployment on staging, אני חושב שיש שם באג בבקשא"
        XCTAssertEqual(Prompts.fix(for: mixed), Prompts.fix(for: "אני יבדוק"))
    }

    func testHebrewPromptIsWrittenInHebrew() {
        // The language the instructions are written in is the strongest signal
        // the model has for which language to answer in.
        XCTAssertTrue(Prompts.fix(for: "אני יבדוק").contains("לעולם אל תתרגם"))
    }

    func testToneDirectionIsAppendedPerRegister() {
        let shorter = Prompts.tone(.shorter, for: "the meeting is tomorrow")
        let friendly = Prompts.tone(.friendly, for: "the meeting is tomorrow")
        XCTAssertNotEqual(shorter, friendly)
        XCTAssertTrue(shorter.contains("strictly fewer words"))
    }

    func testReplyPromptFollowsTheMessageLanguageNotTheContextLabel() {
        // ScreenContext carries a language, but the message is the ground truth.
        let context = ScreenContext(
            appName: "WhatsApp",
            appIcon: "message.fill",
            sender: "יוסי",
            message: "אפשר להזיז את הפגישה למחר?",
            language: .english
        )
        XCTAssertTrue(Prompts.reply(for: context).contains("לעולם אל תתרגם"))
    }
}
