import XCTest

@testable import AIKeyboardCore

@MainActor
final class PersonalCompletionTests: XCTestCase {
    private var predictions = true
    private var dictionary: [String] = []
    private var completeOnIdle = false

    override func setUp() {
        super.setUp()
        predictions = SharedStore.shared.predictions
        dictionary = SharedStore.shared.personalDictionary
        completeOnIdle = SharedStore.shared.completeOnIdle
        SharedStore.shared.predictions = true
        SharedStore.shared.personalDictionary = []
        SharedStore.shared.completeOnIdle = false
    }

    override func tearDown() {
        SharedStore.shared.predictions = predictions
        SharedStore.shared.personalDictionary = dictionary
        SharedStore.shared.completeOnIdle = completeOnIdle
        super.tearDown()
    }

    private func type(_ text: String, on controller: KeyboardController) {
        controller.shift = .off
        for character in text {
            controller.press(character == " " ? .space : .character(String(character)))
        }
    }

    func testCharacterByCharacterEmailLearnsTheEntireAddressAtSpace() {
        for email in ["alex.jones+work42@example.co.uk", "contact_team@example.org", "משתמש@דוגמה.ישראל"] {
            let target = MockTextTarget()
            let controller = KeyboardController(target: target, language: .hebrew)
            type(email, on: controller)
            XCTAssertTrue(
                controller.personal.verbatimTokens(
                    startingWith: String(email.prefix(3)), kind: .email, limit: 3
                ).isEmpty)
            controller.press(.space)
            XCTAssertEqual(
                controller.personal.verbatimTokens(
                    startingWith: String(email.prefix(3)), kind: .email, limit: 3), [email])
            XCTAssertEqual(controller.personal.count(of: email, in: .english), 1)
        }
    }

    func testDomainSegmentsDoNotBecomePrematureSavedAddresses() {
        let target = MockTextTarget()
        let controller = KeyboardController(target: target, language: .english)
        type("alex@example.co", on: controller)
        XCTAssertTrue(controller.personal.verbatimTokens(startingWith: "ale", kind: .email, limit: 3).isEmpty)
        type(".uk", on: controller)
        controller.press(.ret)
        XCTAssertEqual(
            controller.personal.verbatimTokens(startingWith: "ale", kind: .email, limit: 3),
            ["alex@example.co.uk"])
    }

    func testSentencePeriodIsNotSavedAsPartOfTheAddress() {
        let target = MockTextTarget()
        let controller = KeyboardController(target: target, language: .english)
        type("alex@example.org. ", on: controller)
        XCTAssertEqual(
            controller.personal.verbatimTokens(startingWith: "ale", kind: .email, limit: 3),
            ["alex@example.org"])
    }

    func testSendAndDisappearanceShareTheSameCommitForBothKinds() {
        for value in ["alex@example.org", "+972 54 123 6789"] {
            for send in [false, true] {
                let target = MockTextTarget()
                let controller = KeyboardController(target: target, language: .english)
                type(value, on: controller)
                if send {
                    target.text = ""
                    controller.refreshSuggestions()
                } else {
                    controller.learnWordJustCommitted()
                    controller.commitPendingPersonalToken()
                }
                XCTAssertEqual(controller.personal.count(of: value, in: .hebrew), 1, value)
            }
        }
    }

    func testCompletionPreservesCaseAndTextBeforeTheAddress() throws {
        let target = MockTextTarget(text: "כתובת:alex.j")
        let controller = KeyboardController(target: target, language: .hebrew)
        controller.personal.record(
            word: "Alex.Jones+Work@Example.ORG", previous: nil,
            language: .english, permitted: true)
        controller.refreshSuggestions()
        let offer = try XCTUnwrap(controller.suggestions.first { $0.text == "Alex.Jones+Work@Example.ORG" })
        controller.apply(offer)
        XCTAssertEqual(target.text, "כתובת:Alex.Jones+Work@Example.ORG ")
    }

    func testForgottenTokenCannotBeAppliedFromAnOldOffer() throws {
        for value in ["alex@example.org", "0541236789"] {
            let prefix = String(value.prefix(3))
            let target = MockTextTarget(text: prefix)
            let controller = KeyboardController(target: target, language: .hebrew)
            controller.personal.record(word: value, previous: nil, language: .english, permitted: true)
            controller.refreshSuggestions()
            let offer = try XCTUnwrap(controller.suggestions.first { $0.text == value })
            controller.personal.forget(value, in: .hebrew)
            controller.apply(offer)
            XCTAssertEqual(target.text, prefix)
        }
    }

    func testUnknownOrContinuingTailCannotUseTheOrdinaryCandidatePath() {
        for after in [".org", "other", ""] {
            let target = CursorTextTarget(before: "alex@example", after: after)
            target.afterContextIsAvailable = !after.isEmpty
            let controller = KeyboardController(target: target, language: .english)
            controller.personal.record(
                word: "alex@example.org", previous: nil,
                language: .english, permitted: true)
            controller.refreshSuggestions()
            XCTAssertFalse(controller.suggestions.contains { $0.text == "alex@example.org" })
            controller.apply(Suggestion(text: "alex@example.org", language: .english))
            XCTAssertEqual(target.document, "alex@example" + after)
        }
    }

    func testExplicitDictionaryEntriesUseTheSameCompletionPath() throws {
        for value in ["alex@example.org", "0541236789"] {
            SharedStore.shared.personalDictionary = [value]
            let prefix = String(value.prefix(3))
            let target = MockTextTarget(text: prefix)
            let controller = KeyboardController(target: target, language: .hebrew)
            let offer = try XCTUnwrap(controller.suggestions.first { $0.text == value })
            controller.apply(offer)
            XCTAssertEqual(target.text, value + " ")
        }
    }

    func testEmailPrefixDeletionRollsBackWhenHostCannotDeleteAllOfIt() {
        let target = CursorTextTarget(before: "write alex.j")
        let controller = KeyboardController(target: target, language: .english)
        controller.personal.record(
            word: "alex.jones@example.org", previous: nil,
            language: .english, permitted: true)
        target.backwardDeleteLimit = 2
        controller.apply(
            Suggestion(
                text: "alex.jones@example.org", language: .english,
                commit: .verbatimToken(expected: "alex.j")))
        XCTAssertEqual(target.document, "write alex.j")
    }

    func testDifferentTokenKindsCanShareTheSamePrefix() {
        let target = MockTextTarget(text: "054")
        let controller = KeyboardController(target: target, language: .hebrew)
        for value in ["0541236789", "054.team@example.org"] {
            controller.personal.record(word: value, previous: nil, language: .english, permitted: true)
        }
        controller.refreshSuggestions()
        XCTAssertTrue(controller.suggestions.contains { $0.text == "0541236789" })
        XCTAssertTrue(controller.suggestions.contains { $0.text == "054.team@example.org" })
    }

    func testNumericEmailLocalPartDoesNotTeachAPhoneNumber() {
        for email in ["0541236789@example.org", "0541236789.team@example.org", "0541236789_team@example.org"]
        {
            let target = MockTextTarget()
            let controller = KeyboardController(target: target, language: .english)
            type(email + " ", on: controller)
            XCTAssertEqual(
                controller.personal.verbatimTokens(startingWith: "054", kind: .email, limit: 3), [email])
            XCTAssertTrue(controller.personal.phoneNumbers(startingWith: "054", limit: 3).isEmpty)
        }
    }

    func testPhoneWithSentencePeriodStillLearnsAtTheBoundary() {
        let target = MockTextTarget()
        let controller = KeyboardController(target: target, language: .english)
        type("0541236789. ", on: controller)
        controller.press(.ret)
        XCTAssertEqual(controller.personal.phoneNumbers(startingWith: "054", limit: 3), ["0541236789"])
    }

    func testDoubleSpaceCommitsThePhoneBeforeReplacingItsBoundary() {
        let target = MockTextTarget()
        let controller = KeyboardController(target: target, language: .english)
        type("0541236789", on: controller)
        controller.press(.space)
        controller.press(.space)
        XCTAssertEqual(target.text, "0541236789. ")
        XCTAssertEqual(controller.personal.phoneNumbers(startingWith: "054", limit: 3), ["0541236789"])
    }

    func testURLTextCannotTeachAnEmbeddedEmail() {
        for text in [
            "root@server.com/etc", "https://root@server.com/path", "https://site.org/alex@example.org"
        ] {
            let target = MockTextTarget()
            let controller = KeyboardController(target: target, language: .english)
            type(text + " ", on: controller)
            XCTAssertTrue(
                controller.personal.verbatimTokens(startingWith: "roo", kind: .email, limit: 3).isEmpty)
            XCTAssertTrue(
                controller.personal.verbatimTokens(startingWith: "ale", kind: .email, limit: 3).isEmpty)
        }
    }
}
