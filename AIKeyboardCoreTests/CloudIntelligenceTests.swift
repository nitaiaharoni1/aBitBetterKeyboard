import XCTest

@testable import AIKeyboardCore
@testable import AIKeyboardShared

/// Records what it was asked for and answers with whatever the test supplies.
/// The cloud path has never made a real request — there is no API key on the
/// machine this was written on — so everything below the network boundary is
/// what these tests can honestly cover.
private final class StubTransport: CloudTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var _lastRequest: CloudRequest?
    var lastRequest: CloudRequest? {
        lock.lock()
        defer { lock.unlock() }
        return _lastRequest
    }

    let reply: [String: String]
    let failure: AIEngineError?

    init(reply: [String: String] = [:], failure: AIEngineError? = nil) {
        self.reply = reply
        self.failure = failure
    }

    func send(_ request: CloudRequest) async throws -> [String: String] {
        lock.lock()
        _lastRequest = request
        lock.unlock()
        if let failure { throw failure }
        return reply
    }
}

final class CloudIntelligenceTests: XCTestCase {

    func testFixReturnsTheCorrectedField() async throws {
        let transport = StubTransport(
            reply: ["corrections": "dont -> don't", "text": "I don't think we should do it."])
        let engine = CloudIntelligence(transport: transport)

        let result = try await engine.fix("I dont think we should do it")

        XCTAssertEqual(result, "I don't think we should do it.")
    }

    /// The composer seed is one message. A model that only rewrote the last
    /// clause used to put that clause in place of the whole field.
    func testFixKeepsTheWholePlaygroundSeed() async throws {
        let transport = StubTransport(
            reply: [
                "corrections": "dont -> don't, its not -> it doesn't",
                "text": "I don't think we should do it because it doesn't make sense."
            ])
        let result = try await CloudIntelligence(transport: transport).fix(
            "i dont think we should do it because its not make sense")

        XCTAssertEqual(result, "I don't think we should do it because it doesn't make sense.")
    }

    /// `corrections: none` means leave the message. A scrap in `text` used to
    /// fail the fragment guard first and show "nothing came back" instead.
    func testFixKeepsTheMessageWhenTheModelSaidNoneEvenIfTheTextIsAScrap() async throws {
        let source = "omg that meeting was sooo long yesterday im gonna need coffee later"
        XCTAssertTrue(EditScope.isFragment("all good.", of: source))
        let transport = StubTransport(reply: ["corrections": "none", "text": "all good."])

        let result = try await CloudIntelligence(transport: transport).fix(source)

        XCTAssertEqual(result, source)
    }

    func testFixRefusesAFragmentInsteadOfReplacingTheFieldWithIt() async {
        let transport = StubTransport(
            reply: [
                "corrections": "its not -> it doesn't",
                "text": "it doesn't make sense."
            ])
        do {
            _ = try await CloudIntelligence(transport: transport).fix(
                "i dont think we should do it because its not make sense")
            XCTFail("expected .empty")
        } catch let error as AIEngineError {
            XCTAssertEqual(error, .empty)
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    /// The list is filled before the text, so a description that called a missing
    /// apostrophe "not a mistake" made the model write `none` and EditScope threw
    /// the real correction away.
    func testFixAsksTheModelToNameGrammarAndMissingApostrophes() async throws {
        let transport = StubTransport(
            reply: ["corrections": "dont -> don't", "text": "I don't think we should do it."])
        _ = try await CloudIntelligence(transport: transport).fix("I dont think we should do it")

        let corrections = try XCTUnwrap(transport.lastRequest?.fields.first { $0.name == "corrections" })
        XCTAssertTrue(
            corrections.description.contains("its not -> it doesn't"),
            "the field no longer shows a grammar phrase, so the model will not name one")
        XCTAssertTrue(
            corrections.description.contains("missing apostrophe"),
            "the field no longer says a missing apostrophe is a mistake")
        XCTAssertFalse(
            corrections.description.contains("a contraction, a deliberate lowercase"),
            "the old wording told the model that `dont` was not a mistake")
        let text = try XCTUnwrap(transport.lastRequest?.fields.first { $0.name == "text" })
        XCTAssertTrue(
            text.description.contains("whole message"),
            "the text field no longer asks for the whole message")
    }

    /// Same trap as the apostrophe: missing spaces were not in the list of
    /// mistakes, so the model wrote `none` for a jammed Hebrew sentence and
    /// Fix was a silent no-op. The example has to be in the field the model
    /// fills, not only in the instructions it may skim.
    func testFixAsksTheModelToNameWordsStuckTogether() async throws {
        let transport = StubTransport(
            reply: ["corrections": "מהקורה -> מה קורה", "text": "מה קורה"])
        _ = try await CloudIntelligence(transport: transport).fix("מהקורה")

        let corrections = try XCTUnwrap(transport.lastRequest?.fields.first { $0.name == "corrections" })
        XCTAssertTrue(
            corrections.description.contains("hellothere -> hello there"),
            "the field no longer shows an English jammed-words example")
        XCTAssertTrue(
            corrections.description.contains("מהקורה -> מה קורה"),
            "the field no longer shows a Hebrew jammed-words example")
    }

    /// `corrections: none` used to throw the split away even when `text` had
    /// already inserted the spaces. That is the WhatsApp screenshot: the
    /// progress bar ended and the field still said `מהאופישלומהקורה`.
    func testFixKeepsASplitEvenWhenTheModelSaidNone() async throws {
        let transport = StubTransport(
            reply: ["corrections": "none", "text": "מה אופי שלו מה קורה"])
        let result = try await CloudIntelligence(transport: transport).fix("מהאופישלומהקורה")

        XCTAssertEqual(result, "מה אופי שלו מה קורה")
    }

    /// The corrections the model names are what the corrected message is held to,
    /// so an answer that reports none has to come back as the user typed it —
    /// full stop and all. See `EditScope`.
    func testFixReturnsTheMessageUntouchedWhenTheModelFoundNothingWrong() async throws {
        let transport = StubTransport(
            reply: ["corrections": "none", "text": "יאללה סבבה, נדבר אחר כך."])
        let result = try await CloudIntelligence(transport: transport).fix("יאללה סבבה, נדבר אח\"כ")

        XCTAssertEqual(result, "יאללה סבבה, נדבר אח\"כ")
    }

    func testFixSendsTheHebrewPromptForHebrewText() async throws {
        let transport = StubTransport(reply: ["corrections": "יבדוק -> אבדוק", "text": "אני אבדוק את זה"])
        _ = try await CloudIntelligence(transport: transport).fix("אני יבדוק את זה")

        XCTAssertEqual(transport.lastRequest?.instructions, Prompts.fix(for: "אני יבדוק את זה"))
        // Order is load-bearing: the model has to say what is wrong before it
        // writes the version that fixes it, and `propertyOrdering` makes it.
        XCTAssertEqual(transport.lastRequest?.fields.map(\.name), ["corrections", "text"])
    }

    /// The cloud engine exists to serve the scripts the on-device model refuses,
    /// so it must never decline one itself.
    func testCloudAcceptsEveryScript() {
        let engine = CloudIntelligence(transport: StubTransport())
        XCTAssertTrue(engine.canHandle("אני יבדוק", action: .fix))
        XCTAssertTrue(engine.canHandle("こんにちは", action: .reply))
    }

    func testAnEmptyAnswerIsAnErrorRatherThanAnEmptyPanel() async {
        let engine = CloudIntelligence(transport: StubTransport(reply: ["text": "   "]))
        do {
            _ = try await engine.fix("something")
            XCTFail("expected .empty")
        } catch let error as AIEngineError {
            XCTAssertEqual(error, .empty)
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    /// A keyboard extension has no network at all until Full Access is granted,
    /// so this has to be a named state rather than a connection timeout.
    func testNoFullAccessIsReportedBeforeAnyRequest() async {
        let transport = StubTransport(reply: ["text": "unused"])
        let engine = CloudIntelligence(transport: transport, networkAllowed: { false })

        do {
            _ = try await engine.fix("something")
            XCTFail("expected .needsFullAccess")
        } catch let error as AIEngineError {
            XCTAssertEqual(error, .needsFullAccess)
            XCTAssertNil(transport.lastRequest, "nothing should be sent when there is no network")
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testRewriteKeepsThreeLabelledDecisions() async throws {
        let transport = StubTransport(reply: [
            "firstLabel": "Direct no", "firstText": "I don't think we should do this.",
            "secondLabel": "Open", "secondText": "I'm not sold. Can we walk through it again?",
            "thirdLabel": "Counter-proposal", "thirdText": "Could we try a smaller version first?"
        ])

        let variants = try await CloudIntelligence(transport: transport)
            .variants(for: "I dont think we should do it", tone: nil)

        XCTAssertEqual(variants.count, 3)
        XCTAssertEqual(variants.map(\.label), ["Direct no", "Open", "Counter-proposal"])
    }

    /// Rewrite promises three decisions. Two identical strings are a failed
    /// generation, not a result, so they must not reach the panel as choices.
    func testRewriteDropsDuplicateVariants() async throws {
        let transport = StubTransport(reply: [
            "firstLabel": "A", "firstText": "Same answer.",
            "secondLabel": "B", "secondText": "same answer.",
            "thirdLabel": "C", "thirdText": "A different answer."
        ])

        let variants = try await CloudIntelligence(transport: transport)
            .variants(for: "anything", tone: nil)

        XCTAssertEqual(variants.count, 2)
    }

    func testToneReturnsASingleVariantTaggedWithTheRequestedRegister() async throws {
        let transport = StubTransport(reply: [
            "text": "The client hasn't replied, so I want to push Friday's review."
        ])

        let variants = try await CloudIntelligence(transport: transport)
            .variants(
                for:
                    "due to the fact that the client hasnt replied yet, i would like to postpone the review that we had scheduled for friday",
                tone: .shorter
            )

        XCTAssertEqual(variants.count, 1)
        XCTAssertEqual(variants.first?.tone, .shorter)
    }

    /// Tone hands back one string and no choice, so a day the message never
    /// named has to stop there rather than be offered as the user's own words.
    func testToneThatInventedADayFailsRatherThanReplacingTheMessage() async {
        let transport = StubTransport(reply: ["text": "Let's postpone the review to Friday."])

        do {
            _ = try await CloudIntelligence(transport: transport)
                .variants(for: "i would like to postpone the review", tone: .shorter)
            XCTFail("expected .invented")
        } catch let error as AIEngineError {
            XCTAssertEqual(error, .invented)
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    /// The order is the contract: the model settles whether the message can be
    /// agreed to before it writes the reply that agrees to it, and a backend
    /// serving these fields has to preserve that.
    func testReplyAsksWhatIsUnnamedBeforeItAsksForTheReplies() async throws {
        let transport = StubTransport(reply: ["unnamed": "", "accept": "Sure.", "ask": "When?"])
        let context = ScreenContext(
            appName: "Slack", appIcon: "message.fill",
            sender: "Tom", message: "Can we talk?", language: .english
        )

        _ = try await CloudIntelligence(transport: transport).replies(to: context)

        XCTAssertEqual(
            transport.lastRequest?.fields.map(\.name),
            ["unnamed", "addressee", "accept", "pushBack", "ask"]
        )
    }

    func testRewriteNamesTheDecisionAndTheSpecificsBeforeTheThreeVersions() async throws {
        let transport = StubTransport(reply: [
            "decision": "asks for something", "specifics": "tomorrow",
            "firstLabel": "Firm", "firstText": "I need this by tomorrow.",
            "secondLabel": "Ask", "secondText": "Any chance you could get this to me by tomorrow?",
            "thirdLabel": "Negotiable", "thirdText": "Tomorrow if you can, otherwise tell me when."
        ])

        let variants = try await CloudIntelligence(transport: transport)
            .variants(for: "hey i need this by tomorrow please", tone: nil)

        XCTAssertEqual(
            transport.lastRequest?.fields.map(\.name),
            [
                "decision", "specifics", "firstLabel", "firstText", "secondLabel", "secondText", "thirdLabel",
                "thirdText"
            ]
        )
        XCTAssertEqual(variants.count, 3)
    }

    /// The whole point of the guard, reached through the engine rather than
    /// through the guard's own tests: the reply that accepts an unnamed task
    /// does not come back, however well written it is.
    func testAReplyThatAcceptsAnUnnamedTaskNeverReachesThePanel() async throws {
        let transport = StubTransport(reply: [
            "unnamed": "this",
            "accept": "Sure, I'll take a look at it.",
            "pushBack": "Depends what it is. Can you send it over?",
            "ask": "What is it?"
        ])
        let context = ScreenContext(
            appName: "Slack", appIcon: "message.fill",
            sender: "Tom", message: "Can you look at this when you get a chance?", language: .english
        )

        let replies = try await CloudIntelligence(transport: transport).replies(to: context)

        XCTAssertEqual(replies.map(\.intent), ["Push back", "Ask"])
        XCTAssertTrue(replies.allSatisfy { $0.text.contains("?") })
    }

    func testRepliesReturnThreeDistinctDecisions() async throws {
        let transport = StubTransport(reply: [
            "accept": "Sure, 9 works.",
            "pushBack": "I can't do 9, I'm booked.",
            "ask": "Is 9 the only option?"
        ])
        let context = ScreenContext(
            appName: "WhatsApp",
            appIcon: "message.fill",
            sender: "Dana",
            message: "Can we move the call to 9?",
            language: .english
        )

        let replies = try await CloudIntelligence(transport: transport).replies(to: context)

        XCTAssertEqual(replies.map(\.intent), ["Accept", "Push back", "Ask"])
    }

    func testAMissingReplyFieldDropsThatOptionRatherThanFailing() async throws {
        let transport = StubTransport(reply: ["accept": "Sure.", "pushBack": "", "ask": "When?"])
        let context = ScreenContext(
            appName: "WhatsApp", appIcon: "message.fill",
            sender: "Dana", message: "Can we move the call?", language: .english
        )

        let replies = try await CloudIntelligence(transport: transport).replies(to: context)

        XCTAssertEqual(replies.map(\.intent), ["Accept", "Ask"])
    }
}

// BackendTransportTests lives in BackendTransportTests.swift.
