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

    /// **This test used to assert that Cyrillic was `other`, and that was the
    /// bug.** `other` is what routes text to the cloud, and it was also what
    /// Japanese, Korean and Chinese contributed to the on-device model's supported
    /// set — so "unnamed" ended up meaning "supported" and every Cyrillic, Greek,
    /// Arabic and Devanagari message went to a model with no word of it. The
    /// shipped scripts are named now; `other` is reserved for the ones that
    /// genuinely are not.
    func testUnknownScriptIsReportedAsOther() {
        XCTAssertTrue(LanguageDetector.scripts(in: "こんにちは").contains(.other))
        XCTAssertEqual(LanguageDetector.scripts(in: "привет"), [.cyrillic])
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

    /// The instruction the WhatsApp screenshots were missing: jammed words are
    /// a mistake. Without this line the model treated `מהאופישלומהקורה` as
    /// already correct and Fix changed nothing.
    func testFixPromptsCallJammedWordsAMistake() {
        XCTAssertTrue(Prompts.fix(for: "hellothere").contains("hellothere"))
        XCTAssertTrue(Prompts.fix(for: "מהקורה").contains("מהקורה"))
    }

    func testToneDirectionIsAppendedPerRegister() {
        let shorter = Prompts.tone(.shorter, for: "the meeting is tomorrow")
        let friendly = Prompts.tone(.friendly, for: "the meeting is tomorrow")
        XCTAssertNotEqual(shorter, friendly)
        XCTAssertTrue(shorter.contains("strictly fewer words"))
    }

    /// The English prompt is what `Bar/ai-text` is scored against, so Latin text
    /// has to come out of it byte for byte unchanged. The directive is additive
    /// and only for the scripts that need it.
    func testTheEnglishPromptIsUntouchedForLatinText() {
        XCTAssertEqual(Prompts.fix(for: "teh meeting"), Prompts.fix(for: "Merhaba nasılsın"))
        XCTAssertFalse(Prompts.fix(for: "teh meeting").contains("script"))
    }

    /// A message in a script Apple's on-device model does not list goes to the
    /// cloud, and the cloud is told which script it is looking at — the failure
    /// this prevents is an Arabic message answered in English, or a Greek one
    /// transliterated into Latin letters.
    func testANonLatinScriptIsNamedInTheOtherwiseEnglishPrompt() {
        XCTAssertTrue(Prompts.fix(for: "مرحبا كيف حالك").contains("Arabic script"))
        XCTAssertTrue(Prompts.rewrite(for: "привет как дела").contains("Cyrillic script"))
        XCTAssertTrue(Prompts.tone(.shorter, for: "Καλημέρα").contains("Greek script"))
        XCTAssertTrue(Prompts.tone(.shorter, for: "Καλημέρα").contains("strictly fewer words"))
        // Hebrew has a whole instruction set of its own and never takes the line.
        XCTAssertFalse(Prompts.fix(for: "אני יבדוק").contains("script."))
    }

    /// A script nobody named gets no sentence at all. "The message is written in
    /// the This language script" is worse than saying nothing.
    func testAnUnnamedScriptIsNotDescribedToTheModel() {
        XCTAssertEqual(Prompts.fix(for: "こんにちは"), Prompts.fix(for: "hello"))
    }

    /// Reply is the one action handed a language rather than having to read it off
    /// the characters, so it names the language. Cyrillic cannot say whether it is
    /// Russian or Ukrainian; the screen reading can.
    func testReplyNamesTheLanguageTheReadingReported() {
        let context = ScreenContext(
            appName: "Telegram", appIcon: "message.fill", sender: "Олена",
            message: "Привіт, як справи?", language: .ukrainian)
        XCTAssertTrue(Prompts.reply(for: context).contains("Ukrainian"))
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
