import XCTest

@testable import AIKeyboardCore

/// The check that stands between a generated suggestion and the user's send
/// button. It is tested directly rather than only through the corpus because the
/// corpus is scored by a model: it can tell us the rate went up, and it cannot
/// tell us that this exact sentence can never reach a user again.
final class OutputGuardTests: XCTestCase {

    // MARK: Numbers

    func testANumberTheMessageNeverContainedIsAnInvention() {
        XCTAssertEqual(
            OutputGuard.addedSpecifics(in: "Sure, I'll run standup at 9.", notIn: "Can you take standup?"),
            ["9"]
        )
    }

    func testANumberTheMessageDidContainIsFine() {
        XCTAssertTrue(
            OutputGuard.addedSpecifics(
                in: "Yes, Tuesday between 8 and 12 works.",
                notIn: "The plumber can come Tuesday between 8 and 12, does that work?"
            ).isEmpty
        )
    }

    func testDigitsAreCaughtInHebrewToo() {
        XCTAssertEqual(
            OutputGuard.addedSpecifics(in: "אעביר לך 300 שקל", notIn: "תוכל להחזיר לי את הכסף?"),
            ["300"]
        )
    }

    // MARK: Days

    func testADayTheSenderNeverNamedIsAnInvention() {
        XCTAssertEqual(
            OutputGuard.addedSpecifics(in: "Friday works for me.", notIn: "When are you free?"),
            ["friday"]
        )
    }

    func testADayIsMatchedRegardlessOfCase() {
        XCTAssertTrue(
            OutputGuard.addedSpecifics(in: "Friday works.", notIn: "Is friday any good?").isEmpty
        )
    }

    /// Hebrew attaches its prepositions to the word, so the day in "בשבת" is the
    /// same day as the one in "שבת" and neither is an invention of the other.
    func testAHebrewDayIsRecognisedThroughItsAttachedPreposition() {
        XCTAssertTrue(
            OutputGuard.addedSpecifics(in: "בשבת זה מצוין בשבילי", notIn: "מתאים לך שבת?").isEmpty
        )
        XCTAssertEqual(
            OutputGuard.addedSpecifics(in: "נדבר ביום חמישי", notIn: "מתי נוח לך?"),
            ["יום חמישי"]
        )
    }

    /// The prefix rule must not turn every word ending in the same letters into a
    /// weekday: "יושבת" is "sitting", and the ו in front of שבת belongs to it.
    func testAWordThatMerelyEndsInADayIsNotADay() {
        XCTAssertTrue(OutputGuard.addedSpecifics(in: "היא יושבת ליד הדלת", notIn: "איפה היא?").isEmpty)
    }

    func testADayInsideALongerLatinWordIsNotADay() {
        XCTAssertTrue(OutputGuard.addedSpecifics(in: "Check the mondays report", notIn: "any news?").isEmpty)
    }

    // MARK: Promises

    /// The failure this whole file exists for: a message with no task in it came
    /// back with a promise about when the task would be finished.
    func testAPromiseAboutTimingIsAnInventionWhenNothingAskedForOne() {
        XCTAssertEqual(
            OutputGuard.addedSpecifics(
                in: "I'll look at it as soon as I can.",
                notIn: "Can you look at this when you get a chance?"
            ),
            ["as soon as i can"]
        )
    }

    func testHebrewPromisesAreCaughtThroughTheirPreposition() {
        XCTAssertEqual(
            OutputGuard.addedSpecifics(in: "אני מטפל בזה בהקדם", notIn: "ה-app קורס לי"),
            ["הקדם"]
        )
        XCTAssertEqual(OutputGuard.addedSpecifics(in: "אני שולח מיד", notIn: "שלח לי את הקובץ"), ["מיד"])
    }

    /// "מיד" is a whole word, not the first three letters of "always" or of
    /// "information". Getting this wrong would reject ordinary Hebrew.
    func testHebrewWordsThatMerelyStartWithAPromiseAreNotPromises() {
        XCTAssertTrue(OutputGuard.addedSpecifics(in: "אני תמיד שמח לעזור", notIn: "תודה").isEmpty)
        XCTAssertTrue(OutputGuard.addedSpecifics(in: "אין לי מידע על זה", notIn: "מה קורה?").isEmpty)
    }

    /// The line the rules are drawn around. A bare time word states a limit as
    /// often as it makes a promise, and the reference answer to the corpus's own
    /// hallucination probe declines with exactly this sentence — so a rule
    /// against every time word would reject the answer we are aiming for.
    func testStatingWhenSomethingWillNotHappenIsNotAPromise() {
        XCTAssertTrue(
            OutputGuard.addedSpecifics(
                in: "Happy to, though it won't be today. What is it?",
                notIn: "Can you look at this when you get a chance?"
            ).isEmpty
        )
    }

    func testAPromiseTheMessageItselfMadeIsNotAnInvention() {
        XCTAssertTrue(
            OutputGuard.addedSpecifics(in: "Sure, asap.", notIn: "Can you send it asap?").isEmpty
        )
    }

    // MARK: Filtering

    func testDuplicateCandidatesCollapseToOne() {
        let kept = OutputGuard.keep(
            [
                (label: "A", text: "Same answer."), (label: "B", text: "same answer."),
                (label: "C", text: "A different answer.")
            ],
            groundedIn: "anything"
        )
        XCTAssertEqual(kept.map(\.label), ["A", "C"])
    }

    func testCandidatesKeepTheOrderTheyWereGeneratedIn() {
        let kept = OutputGuard.keep(
            [(label: "A", text: "First."), (label: "B", text: "Second."), (label: "C", text: "Third.")],
            groundedIn: "anything"
        )
        XCTAssertEqual(kept.map(\.text), ["First.", "Second.", "Third."])
    }

    func testACandidateThatInventedSomethingIsDroppedRatherThanRepaired() {
        let kept = OutputGuard.keep(
            [(label: "A", text: "Yes, 9 works."), (label: "B", text: "Yes, that works.")],
            groundedIn: "Does that work for you?"
        )
        XCTAssertEqual(kept.map(\.label), ["B"])
    }

    /// When the message cannot be agreed to as it stands, agreeing without
    /// asking is the failure however politely it is written.
    func testNothingSurvivesWithoutAQuestionOnceTheMessageIsUnanswerable() {
        let kept = OutputGuard.keep(
            [
                (label: "A", text: "Sure, I'll take a look at it."),
                (label: "B", text: "Sure. What am I looking at?")
            ],
            groundedIn: "Can you look at this when you get a chance?",
            mustAsk: true
        )
        XCTAssertEqual(kept.map(\.label), ["B"])
    }

    func testAskingIsEnoughEvenWhenTheReplyAlsoAgrees() {
        XCTAssertTrue(OutputGuard.asks("Sure. What am I looking at?"))
        XCTAssertTrue(OutputGuard.asks("בטח. על מה מדובר?"))
        XCTAssertFalse(OutputGuard.asks("Sure, I'll take a look."))
    }

    // MARK: Assembly

    func testRepliesThatAllInventedSomethingFailRatherThanBeingShown() {
        XCTAssertThrowsError(
            try ReplyOption.vetted(
                accept: "Sure, I'll have it done by Friday.",
                pushBack: "I can't do Friday.",
                ask: "Is Friday the deadline?",
                against: "Can you get to this?",
                unnamed: ""
            )
        ) { error in
            XCTAssertEqual(error as? AIEngineError, .invented)
        }
    }

    /// `.empty` and `.invented` are different states and the user is told which:
    /// nothing came back, versus what came back was withheld.
    func testAReplyWithNoContentAtAllIsEmptyRatherThanInvented() {
        XCTAssertThrowsError(
            try ReplyOption.vetted(
                accept: "", pushBack: "", ask: "", against: "anything", unnamed: "")
        ) { error in
            XCTAssertEqual(error as? AIEngineError, .empty)
        }
    }

    func testTheSurvivingRepliesKeepTheirIntentAndIcon() throws {
        let options = try ReplyOption.vetted(
            accept: "Yes, that works.",
            pushBack: "That doesn't work for me.",
            ask: "What time?",
            against: "Does that work?",
            unnamed: ""
        )
        XCTAssertEqual(options.map(\.intent), ["Accept", "Push back", "Ask"])
        XCTAssertEqual(options.map(\.icon), ["checkmark", "hand.raised", "questionmark"])
    }

    func testAnUnnamedTaskLeavesOnlyTheRepliesThatAskAboutIt() throws {
        let options = try ReplyOption.vetted(
            accept: "Sure, I'll take a look at it.",
            pushBack: "Depends what it is. Can you send it over?",
            ask: "What is it?",
            against: "Can you look at this when you get a chance?",
            unnamed: "this"
        )
        XCTAssertEqual(options.map(\.intent), ["Push back", "Ask"])
    }

    /// The field is required, so a model with nothing to report fills it with a
    /// placeholder. Reading that as "something is unnamed" would silently drop
    /// every reply that does not happen to end in a question mark.
    func testAPlaceholderInTheUnnamedFieldIsNotAnUnnamedTask() throws {
        for placeholder in ["", "  ", "none", "None", "N/A", "null", "-"] {
            let options = try ReplyOption.vetted(
                accept: "Yes, that works.",
                pushBack: "That doesn't work for me.",
                ask: "What time?",
                against: "Does that work?",
                unnamed: placeholder
            )
            XCTAssertEqual(options.count, 3, "\(placeholder.debugDescription) should not gate replies")
        }
    }

    func testRewriteVariantsThatAllInventedSomethingFailRatherThanBeingShown() {
        XCTAssertThrowsError(
            try RewriteVariant.vetted(
                [
                    (label: "A", text: "I need this by Monday."),
                    (label: "B", text: "Can I have this by Monday?")
                ],
                against: "i need this soon"
            )
        ) { error in
            XCTAssertEqual(error as? AIEngineError, .invented)
        }
    }

    func testAnEmptyRewriteLabelBecomesNoLabelRatherThanABlankChip() throws {
        let variants = try RewriteVariant.vetted(
            [(label: "", text: "I need this by tomorrow.")],
            against: "hey i need this by tomorrow please"
        )
        XCTAssertNil(variants.first?.label)
    }
}
