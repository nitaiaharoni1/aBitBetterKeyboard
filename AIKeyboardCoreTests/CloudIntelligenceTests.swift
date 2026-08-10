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
// MARK: - Wire format

/// Covers how `BackendTransport` builds its request and reads the reply. The
/// HTTP call itself is not exercised here: no backend exists yet, and the app
/// deliberately holds no provider credential of its own.
final class BackendTransportTests: XCTestCase {

    func testDecodesTheFieldsObject() throws {
        let body = #"{"fields": {"text": "I don't think so."}}"#
        XCTAssertEqual(try BackendTransport.decode(Data(body.utf8))["text"], "I don't think so.")
    }

    /// A provider safety block has to read as a decision about the text, not as
    /// the service being down, so the backend flags it and the app says so.
    func testAnExplicitRefusalIsSurfacedAsARefusal() {
        let body = #"{"refused": true}"#
        XCTAssertThrowsError(try BackendTransport.decode(Data(body.utf8))) { error in
            XCTAssertEqual(error as? AIEngineError, .refused)
        }
    }

    func testAReplyWithNoFieldsIsReportedAsEmpty() {
        XCTAssertThrowsError(try BackendTransport.decode(Data("{}".utf8))) { error in
            XCTAssertEqual(error as? AIEngineError, .empty)
        }
    }

    func testUnreadableBodyIsReportedRatherThanCrashing() {
        XCTAssertThrowsError(try BackendTransport.decode(Data("not json".utf8)))
    }

    func testStatusCodesMapToActionableErrors() {
        let empty = Data("{}".utf8)
        XCTAssertEqual(BackendTransport.mapped(status: 401, body: empty), .cloudNotConfigured)
        XCTAssertEqual(BackendTransport.mapped(status: 422, body: empty), .refused)
        XCTAssertEqual(BackendTransport.mapped(status: 413, body: empty), .inputTooLong)
        if case .network = BackendTransport.mapped(status: 503, body: empty) {
        } else {
            XCTFail("a 5xx should read as the service being unreachable")
        }
    }

    /// **The two states that used to mean "no cloud" now mean "the built-in one",
    /// and that swap is the whole fix.**
    ///
    /// An absent or empty `cloudBackendURL` is what every stock install had, and
    /// before 2026-08-10 it answered nil. Nil is not a cosmetic result: it is why
    /// Hebrew Fix, Rewrite, Tone and Reply had no engine for the life of the
    /// install, and why the best-effort branch could not rescue them either, since
    /// Apple's on-device model rejects a session whose instructions are Hebrew.
    ///
    /// This asserts the opposite of what the shipped-and-broken build returned, so
    /// it fails against it rather than passing for the wrong reason.
    func testAnAbsentOrEmptyURLFallsBackToTheBundledBackend() {
        let suiteName = "BackendTransportFallbackTests"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.removePersistentDomain(forName: suiteName)

        XCTAssertNotNil(
            BackendTransport.configured(defaults: defaults),
            "a stock install stores nothing, and has to reach the shipped backend")
        // Named exactly, not just "something came back". `configured()` hides its
        // `baseURL`, so without this the test would pass against a fallback that
        // resolved to any URL at all.
        XCTAssertEqual(
            BackendTransport.effectiveURL(defaults: defaults), BackendTransport.bundledDefaultURL)
        XCTAssertTrue(BackendTransport.usesBundledBackend(defaults: defaults))

        // Whitespace is the same state as empty: `CloudModelView` trims before it
        // saves, so a field holding spaces is a field the user cleared.
        for blank in ["", "   ", "\n"] {
            defaults.set(blank, forKey: "cloudBackendURL")
            XCTAssertNotNil(
                BackendTransport.configured(defaults: defaults),
                "clearing the field puts the shipped backend back, it does not switch AI off")
        }

        // A backend the user typed still wins over the one that ships.
        defaults.set("https://api.example.com", forKey: "cloudBackendURL")
        XCTAssertNotNil(BackendTransport.configured(defaults: defaults))
        XCTAssertEqual(BackendTransport.effectiveURL(defaults: defaults), "https://api.example.com")
        XCTAssertFalse(BackendTransport.usesBundledBackend(defaults: defaults))

        // And a stored value that is not a web address is still no backend at all.
        // This is the one route to nil left, and `CloudModelView` refuses to save
        // it in the first place.
        defaults.set("not a url", forKey: "cloudBackendURL")
        XCTAssertNil(BackendTransport.configured(defaults: defaults))
    }

    /// **"There is somewhere to send" is not "the cloud works", and shipping a URL
    /// is what forced them apart.**
    ///
    /// Every screen that renders a cloud claim reads `isReady`: Settings' "Set
    /// up" row, the onboarding step in `SetupState`, the dictation screen's cloud
    /// card, the Screen Context prompt, and `ScreenReadService.canRead`, which is
    /// what lets a broadcast live. `configured()` is true from the first launch
    /// now, so had they kept reading it, a fresh install would tick off a
    /// completed setup and start recording somebody's screen for a keyboard that
    /// 401s on every call.
    func testReadinessNeedsATokenForTheShippedBackendButNotForYourOwn() {
        let suiteName = "BackendTransportReadinessTests"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.removePersistentDomain(forName: suiteName)

        // A fresh install: the shipped address is in force and no token has been
        // pasted in. There is somewhere to send and nothing that would be accepted.
        XCTAssertNotNil(BackendTransport.configured(defaults: defaults))
        XCTAssertFalse(
            BackendTransport.isReady(defaults: defaults),
            "the shipped backend gates on a bearer, so no token is an unfinished setup")

        defaults.set("   ", forKey: "cloudBackendToken")
        XCTAssertFalse(
            BackendTransport.isReady(defaults: defaults),
            "whitespace is not a token — it is dropped before the header is built")

        defaults.set("s3cret", forKey: "cloudBackendToken")
        XCTAssertTrue(BackendTransport.isReady(defaults: defaults))

        // Naming the shipped address explicitly is the same state as leaving it
        // blank, and must not be read as "a backend of my own with no gate".
        defaults.set(BackendTransport.bundledDefaultURL, forKey: "cloudBackendURL")
        defaults.removeObject(forKey: "cloudBackendToken")
        XCTAssertFalse(BackendTransport.isReady(defaults: defaults))

        // Somebody else's backend with no token is a real backend — a service run
        // without `BACKEND_TOKEN` accepts everyone. Refusing it here would turn a
        // working setup into "no cloud model".
        defaults.set("https://my-own-backend.example.com", forKey: "cloudBackendURL")
        XCTAssertTrue(
            BackendTransport.isReady(defaults: defaults),
            "a self-hosted backend with no gate is still a working backend")

        // And a value that is not a web address is not ready however it is dressed.
        defaults.set("not a url", forKey: "cloudBackendURL")
        defaults.set("s3cret", forKey: "cloudBackendToken")
        XCTAssertFalse(BackendTransport.isReady(defaults: defaults))
    }

    /// The constant itself has to be a URL the transport will accept.
    ///
    /// Worth its own assertion rather than trusting the test above: the fallback
    /// runs `bundledDefaultURL` through exactly the same two questions as a typed
    /// value, so a typo in it does not fail loudly — it returns nil from every
    /// `configured()` call in all three processes and restores the original bug
    /// with no error anywhere.
    func testTheBundledBackendURLIsOneTheTransportAccepts() throws {
        let url = try XCTUnwrap(URL(string: BackendTransport.bundledDefaultURL))
        XCTAssertEqual(url.scheme, "https", "a keyboard must not post the user's text over http")
        XCTAssertNotNil(url.host)
    }
}
