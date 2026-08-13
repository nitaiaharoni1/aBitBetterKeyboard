import XCTest

@testable import AIKeyboardCore

/// The check that keeps a Fix inside the mistakes it was asked to fix.
///
/// It is tested here rather than only through `Bar/ai-text` because the corpus is
/// scored by a model, one entry at a time: it can say the rate went up, and it
/// cannot say that this exact word can never be respelled behind the user's back
/// again. These are the cases that must never regress, whatever the score does.
final class EditScopeTests: XCTestCase {

    // MARK: Nothing wrong

    /// The entry the whole file exists for on the Hebrew side: slang, an
    /// abbreviation, no full stop, nothing wrong. Whatever the model wrote, a
    /// message it found no mistakes in comes back exactly as the user typed it.
    func testAMessageWithNoMistakesComesBackUntouched() {
        XCTAssertEqual(
            EditScope.applied(
                "יאללה סבבה, נדבר אחר כך.", to: "יאללה סבבה, נדבר אח\"כ", corrections: "none"),
            "יאללה סבבה, נדבר אח\"כ"
        )
    }

    func testAFullStopIsNotAddedToAMessageWithNothingWrongInIt() {
        XCTAssertEqual(
            EditScope.applied(
                "צריך לעשות refactor ל-service הזה לפני ה-release.",
                to: "צריך לעשות refactor ל-service הזה לפני ה-release",
                corrections: "none"
            ),
            "צריך לעשות refactor ל-service הזה לפני ה-release"
        )
    }

    /// The field is required, so a model with nothing to report writes a
    /// placeholder rather than leaving it blank.
    func testEveryWayOfSayingNothingIsWrongCountsAsNothingIsWrong() {
        for placeholder in ["", "  ", "none", "None", "N/A", "null", "-", "nothing", "אין שגיאות"] {
            XCTAssertTrue(
                EditScope.declaresNothing(placeholder),
                "\(placeholder.debugDescription) means nothing is wrong")
        }
        XCTAssertFalse(EditScope.declaresNothing("teh -> the"))
    }

    // MARK: Changes the model did not name

    /// `והכל` and `והכול` are both correct Hebrew. Respelling one as the other is
    /// a house-style preference, and it is the change that makes people turn
    /// autocorrect off — so it goes back, and the English error the model was
    /// actually right about stays fixed.
    func testHebrewTheModelRespelledWithoutCallingItAMistakeGoesBack() {
        XCTAssertEqual(
            EditScope.applied(
                "העליתי את התיקון ל-staging והכול עובד, it's fine.",
                to: "העליתי את התיקון ל-staging והכל עובד, its fine",
                corrections: "its -> it's"
            ),
            "העליתי את התיקון ל-staging והכל עובד, it's fine"
        )
    }

    /// Named or not, the two accepted Hebrew spellings of a word are not a
    /// correction: a model that lists the respelling as a mistake is still wrong.
    func testAnAlternativeHebrewSpellingIsNotACorrectionEvenWhenTheModelClaimsItIs() {
        XCTAssertEqual(
            EditScope.applied("והכול עובד", to: "והכל עובד", corrections: "והכל -> והכול"),
            "והכל עובד"
        )
    }

    /// The other side of that rule. `תגדי` → `תגיד` moves a י rather than adding
    /// one, and `יבדוק` → `אבדוק` swaps a letter, so both are real corrections
    /// and both survive.
    func testARealHebrewCorrectionIsNotMistakenForASpellingVariant() {
        XCTAssertEqual(
            EditScope.applied(
                "שלחתי לך את הקובץ אתמול בערב, תגיד לי אם קיבלת",
                to: "שלחתי לך את הקובץ אתמול בערב, תגדי לי אם קיבלת",
                corrections: "תגדי -> תגיד"
            ),
            "שלחתי לך את הקובץ אתמול בערב, תגיד לי אם קיבלת"
        )
        XCTAssertEqual(
            EditScope.applied("אני אבדוק את זה", to: "אני יבדוק את זה", corrections: "יבדוק -> אבדוק"),
            "אני אבדוק את זה"
        )
    }

    func testAWordSwappedForAnotherWithoutBeingNamedGoesBack() {
        XCTAssertEqual(
            EditScope.applied(
                "I think we should ship this on Thursday afternoon",
                to: "I think we should shipp this on Thurdsay afternon",
                corrections: "Thurdsay -> Thursday, afternon -> afternoon"
            ),
            "I think we should shipp this on Thursday afternoon"
        )
    }

    /// Measured: the model prefixed a loanword it had no business touching.
    func testAPrefixTheModelAddedToALoanwordGoesBack() {
        XCTAssertEqual(
            EditScope.applied(
                "צריך לעשות ל-refactor ל-service הזה לפני ה-release",
                to: "צריך לעשות refactor ל-service הזה לפני ה-release",
                corrections: "חסר ניקוד"
            ),
            "צריך לעשות refactor ל-service הזה לפני ה-release"
        )
    }

    func testAWordTheModelDeletedWithoutNamingItComesBack() {
        XCTAssertEqual(
            EditScope.applied(
                "that meeting was long I'm gonna need coffee",
                to: "that meeting was sooo long 😅 im gonna need coffee",
                corrections: "im -> I'm"
            ),
            "that meeting was sooo long 😅 I'm gonna need coffee"
        )
    }

    // MARK: Contractions

    /// A missing apostrophe is a typo, not shorthand: `dont` is `don't`, and
    /// expanding it rewrites the register of a message the user only wanted
    /// spellchecked. This holds whichever way the model described the change.
    func testAnExpandedContractionComesBackAsAContraction() {
        XCTAssertEqual(
            EditScope.applied(
                "Please do not forget to send the invoice before the 15th, otherwise finance will not process it this month.",
                to:
                    "Please dont forget to send the invoice before the 15th, otherwise finance wont process it this month.",
                corrections: "dont -> do not, wont -> will not"
            ),
            "Please don't forget to send the invoice before the 15th, otherwise finance won't process it this month."
        )
    }

    func testAnExpandedContractionKeepsItsSentenceCaseAndPunctuation() {
        XCTAssertEqual(
            EditScope.applied(
                "Do not worry about it.", to: "Dont worry about it.", corrections: "Dont -> Do not"),
            "Don't worry about it."
        )
        XCTAssertEqual(
            EditScope.applied("I am on it, thanks!", to: "im on it, thanks!", corrections: "im -> I am"),
            "I'm on it, thanks!"
        )
    }

    /// `ill` and `lets` are ordinary words as well as contractions, so neither is
    /// in the list. A rule that rewrites "I was ill last week" is worse than the
    /// one it fixes.
    func testAnOrdinaryWordThatLooksLikeAContractionIsLeftAlone() {
        XCTAssertEqual(
            EditScope.applied(
                "Sorry, I was ill last week", to: "sorry i was ill last week",
                corrections: "sorry i -> Sorry, I"),
            "Sorry, I was ill last week"
        )
    }

    // MARK: What is not a change

    /// Punctuation is invisible to the scope check, because the reference answers
    /// add question marks and commas without ever listing them as mistakes — and
    /// a question that comes back without its question mark is a failure in both
    /// languages.
    func testPunctuationTheModelAddedSurvives() {
        XCTAssertEqual(
            EditScope.applied(
                "מה קורה? אני מנסה להתקשר אליך כל הבוקר",
                to: "מה קורה אני מנסה להתקשר אליך כל הבוקר",
                corrections: "חסר סימן שאלה"
            ),
            "מה קורה? אני מנסה להתקשר אליך כל הבוקר"
        )
    }

    func testCapitalisationTheModelFixedSurvives() {
        XCTAssertEqual(
            EditScope.applied(
                "Can you send me the ID for the sprint ticket?",
                to: "can you send me the id for the sprint ticket",
                corrections: "missing question mark"
            ),
            "Can you send me the ID for the sprint ticket?"
        )
    }

    // MARK: Shape

    func testLineBreaksInTheMessageSurvive() {
        XCTAssertEqual(
            EditScope.applied(
                "Hi Dana,\n\nThe deck is attached.\nThanks",
                to: "Hi Dana,\n\nThe dekc is attached.\nThanks",
                corrections: "dekc -> deck"
            ),
            "Hi Dana,\n\nThe deck is attached.\nThanks"
        )
    }

    func testARestoredWordAtTheEndOfTheMessageDoesNotSwallowTheSpaceAfterIt() {
        XCTAssertEqual(
            EditScope.applied(
                "send it Monday please", to: "send it monady plz", corrections: "monady -> Monday"),
            "send it Monday plz"
        )
    }

    // MARK: Words stuck together

    /// The WhatsApp screenshots. Jammed Hebrew is several words, not one already-
    /// correct word, and `none` used to throw the split away so Fix was a no-op.
    func testJammedHebrewIsSplitEvenWhenTheModelSaidNone() {
        XCTAssertEqual(
            EditScope.applied(
                "מה אופי שלו מה קורה", to: "מהאופישלומהקורה", corrections: "none"),
            "מה אופי שלו מה קורה"
        )
        XCTAssertEqual(
            EditScope.applied(
                "היי מה אופי שלו מה קורה", to: "היי מהאופישלומהקורה", corrections: "none"),
            "היי מה אופי שלו מה קורה"
        )
    }

    /// The list described the mistake in words rather than as `wrong -> right`,
    /// so the jammed token was not in the named set and the shape check put it
    /// back. Spacing is not a word swap.
    func testJammedHebrewIsSplitEvenWhenTheModelNamedTheChangeBadly() {
        XCTAssertEqual(
            EditScope.applied(
                "מה אופי שלו מה קורה", to: "מהאופישלומהקורה", corrections: "חסרים רווחים"),
            "מה אופי שלו מה קורה"
        )
        XCTAssertEqual(
            EditScope.applied(
                "hello there", to: "hellothere", corrections: "missing spaces"),
            "hello there"
        )
    }

    /// Joining is the opposite recovery and is still refused on `none`.
    func testJammedWordsAreNotJoinedBackTogetherWhenTheModelSaidNone() {
        XCTAssertEqual(
            EditScope.applied("מהקורה", to: "מה קורה", corrections: "none"),
            "מה קורה"
        )
    }

    /// A Hebrew full stop on `none` is still tidying, not a split.
    func testAFullStopIsStillNotAWhitespaceSplit() {
        XCTAssertFalse(
            EditScope.splitsOnlyByWhitespace("מעולה, נתראה מחר בבוקר.", of: "מעולה, נתראה מחר בבוקר"))
        XCTAssertTrue(
            EditScope.splitsOnlyByWhitespace("מה קורה", of: "מהקורה"))
    }

    // MARK: Full stops

    /// Measured: the model kept putting a full stop on the end of Hebrew messages
    /// that had nothing wrong with them, and once on one it had genuinely
    /// corrected. No Hebrew or code-switched reference in the corpus ends in one.
    func testAFullStopIsNotAddedToTheEndOfAHebrewMessage() {
        XCTAssertEqual(
            EditScope.applied(
                "מעולה, נתראה מחר בבוקר.", to: "מעולה, נתראה מחר בבוקר", corrections: " -> ."),
            "מעולה, נתראה מחר בבוקר"
        )
        XCTAssertEqual(
            EditScope.applied(
                "שלחתי לך את הקובץ, תגיד לי אם קיבלת.",
                to: "שלחתי לך את הקובץ, תגדי לי אם קיבלת",
                corrections: "תגדי -> תגיד"
            ),
            "שלחתי לך את הקובץ, תגיד לי אם קיבלת"
        )
    }

    func testAFullStopTheWriterTypedThemselvesStays() {
        XCTAssertEqual(
            EditScope.applied(
                "תודה רבה, קיבלתי. אני עובר על זה עכשיו.",
                to: "תודה רבה, קיבלתי. אני עובר על זה עכשיו.",
                corrections: "none"
            ),
            "תודה רבה, קיבלתי. אני עובר על זה עכשיו."
        )
    }

    /// English is the other way round: four of the corpus's own reference answers
    /// close a corrected English sentence with a full stop the writer left off.
    func testAFullStopIsStillAddedToAnEnglishMessage() {
        XCTAssertEqual(
            EditScope.applied(
                "He said \"I don't know\" and left it there.",
                to: "he said \"i dont know\" and left it there",
                corrections: "he -> He, i -> I, dont -> don't"
            ),
            "He said \"I don't know\" and left it there."
        )
    }

    // MARK: A leftover scrap

    /// The model sometimes answers with only the last clause. Applying that
    /// would delete the rest of the field, which is the opposite of Fix.
    func testALastClauseIsAFragmentOfTheMessage() {
        XCTAssertTrue(
            EditScope.isFragment(
                "it doesn't make sense.",
                of: "i dont think we should do it because its not make sense"))
        XCTAssertFalse(
            EditScope.isFragment(
                "I don't think we should do it because it doesn't make sense.",
                of: "i dont think we should do it because its not make sense"))
    }

    func testAShortMessageIsNeverTreatedAsAFragmentOfItself() {
        XCTAssertFalse(EditScope.isFragment("thanks", of: "thx u"))
        XCTAssertFalse(EditScope.isFragment("אני אבדוק את זה", of: "אני יבדוק את זה"))
    }

    /// The playground seed, with the grammar named the way the cloud field now
    /// asks for it. A list that only mentioned `dont` used to put `its not make
    /// sense` back, so tapping Fix looked like it had ignored the sentence.
    func testThePlaygroundSeedKeepsItsGrammarWhenTheListNamesThePhrase() {
        XCTAssertEqual(
            EditScope.applied(
                "I don't think we should do it because it doesn't make sense.",
                to: "i dont think we should do it because its not make sense",
                corrections: "dont -> don't, its not -> it doesn't"
            ),
            "I don't think we should do it because it doesn't make sense."
        )
    }

    // MARK: Without a list

    /// The on-device model is not asked what it corrected, because asking made it
    /// worse at correcting. What survives without a list is the pair of changes no
    /// model gets right: an expanded contraction, and a Hebrew word respelled into
    /// its other accepted spelling.
    func testAnExpandedContractionIsRepairedWithNoListAtAll() {
        XCTAssertEqual(
            EditScope.repaired(
                "Please do not forget to send the invoice.", to: "Please dont forget to send the invoice."),
            "Please don't forget to send the invoice."
        )
    }

    func testAHebrewSpellingVariantGoesBackWithNoListAtAll() {
        XCTAssertEqual(
            EditScope.repaired("והכול עובד, it's fine", to: "והכל עובד, its fine"),
            "והכל עובד, it's fine"
        )
    }

    /// The other half of the check is exactly what is given up: with no list, a
    /// word swap has nothing to be measured against, so it is taken on trust.
    func testWithNoListAnUnexplainedWordChangeIsLeftAlone() {
        XCTAssertEqual(
            EditScope.repaired("the deck is ready", to: "the dekc is redy"),
            "the deck is ready"
        )
    }

    func testWithNoListARealCorrectionStillSurvives() {
        XCTAssertEqual(
            EditScope.repaired(
                "I'll send you the updated presentation after the standup tomorrow.",
                to: "Ill sedn you teh updated presentaion after the standup tommorow"),
            "I'll send you the updated presentation after the standup tomorrow."
        )
    }

    // Corpus tests live in EditScopeCorpusTests.swift.
}
