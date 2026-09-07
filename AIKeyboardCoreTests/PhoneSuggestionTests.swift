import XCTest

@testable import AIKeyboardCore

@MainActor
final class PhoneSuggestionTests: XCTestCase {
    private var predictions = true
    private var autocorrect = AutocorrectLevel.full
    private var completeOnIdle = false

    override func setUp() {
        super.setUp()
        predictions = SharedStore.shared.predictions
        autocorrect = SharedStore.shared.autocorrectLevel
        completeOnIdle = SharedStore.shared.completeOnIdle
        SharedStore.shared.predictions = true
        SharedStore.shared.autocorrectLevel = .full
        SharedStore.shared.completeOnIdle = false
    }

    override func tearDown() {
        SharedStore.shared.predictions = predictions
        SharedStore.shared.autocorrectLevel = autocorrect
        SharedStore.shared.completeOnIdle = completeOnIdle
        super.tearDown()
    }

    private func type(_ text: String, on controller: KeyboardController) {
        for character in text {
            controller.press(character == " " ? .space : .character(String(character)))
        }
    }

    func testReturnCommitsTypedPhoneAndNextPrefixOffersItAcrossLanguages() throws {
        let target = MockTextTarget()
        let controller = KeyboardController(target: target, language: .hebrew)
        type("0541236789", on: controller)
        controller.press(.ret)
        XCTAssertEqual(controller.personal.phoneNumbers(startingWith: "054", limit: 3), ["0541236789"])
        target.text = "054"
        controller.refreshSuggestions()
        let offer = try XCTUnwrap(controller.suggestions.first { $0.text == "0541236789" })
        XCTAssertFalse(offer.isDefault)
        controller.apply(offer)
        XCTAssertEqual(target.text, "0541236789 ")
    }

    func testFormattedPhoneDoesNotLearnPlausiblePartialAtInternalSpace() {
        let target = MockTextTarget()
        let controller = KeyboardController(target: target, language: .english)
        type("+972 54 123 ", on: controller)
        XCTAssertTrue(controller.personal.learnedWords().isEmpty)
        type("6789", on: controller)
        controller.press(.ret)
        XCTAssertEqual(controller.personal.learnedWords().map(\.word), ["+972 54 123 6789"])
    }

    func testSendWithoutFinalSpaceCommitsPhoneDraft() {
        let target = MockTextTarget()
        let controller = KeyboardController(target: target, language: .hebrew)
        type("0541236789", on: controller)
        target.text = ""
        controller.refreshSuggestions()
        XCTAssertEqual(controller.personal.phoneNumbers(startingWith: "054", limit: 3), ["0541236789"])
    }

    func testDisappearanceCommitCapturesPhoneWithoutFinalSpace() {
        let target = MockTextTarget()
        let controller = KeyboardController(target: target, language: .hebrew)
        type("0541236789", on: controller)
        controller.commitPendingPersonalToken()
        XCTAssertEqual(controller.personal.phoneNumbers(startingWith: "054", limit: 3), ["0541236789"])
    }

    func testStartingWordAfterFormattedNumberCommitsWholePhone() {
        let target = MockTextTarget()
        let controller = KeyboardController(target: target, language: .english)
        type("+972 54 123 6789 c", on: controller)
        XCTAssertEqual(controller.personal.learnedWords().map(\.word), ["+972 54 123 6789"])
    }

    func testSerialNumbersNeverBecomePhoneDrafts() {
        for serial in ["abc0541236789", "0541236789abc"] {
            let target = MockTextTarget()
            let controller = KeyboardController(target: target, language: .english)
            type(serial, on: controller)
            controller.press(.ret)
            XCTAssertTrue(controller.personal.phoneNumbers(startingWith: "054", limit: 3).isEmpty, serial)
        }
    }

    func testSpaceCannotReplaceLastGroupWithTheFormattedEcho() {
        let target = MockTextTarget(text: "+972 54")
        let controller = KeyboardController(target: target, language: .hebrew)
        controller.personal.recordPhoneNumber("+972 54 123 6789", language: .hebrew, permitted: true)
        controller.refreshSuggestions()
        XCTAssertTrue(controller.suggestions.contains { $0.text == "+972 54 123 6789" })
        controller.press(.space)
        XCTAssertEqual(target.text, "+972 54 ")
    }

    func testPhoneOfferRefusesCaretInsideFormattedNumber() {
        let target = CursorTextTarget(before: "+972 54", after: " 123 6789")
        let controller = KeyboardController(target: target, language: .hebrew)
        controller.personal.recordPhoneNumber("+972 54 123 6789", language: .hebrew, permitted: true)
        let offer = Suggestion(
            text: "+972 54 123 6789", language: .hebrew, commit: .verbatimToken(expected: "+972 54"))
        controller.apply(offer)
        XCTAssertEqual(target.document, "+972 54 123 6789")
    }

    func testForgottenPhoneCannotBeInsertedFromStaleOffer() throws {
        let target = MockTextTarget(text: "054")
        let controller = KeyboardController(target: target, language: .hebrew)
        controller.personal.recordPhoneNumber("0541236789", language: .hebrew, permitted: true)
        controller.refreshSuggestions()
        let offer = try XCTUnwrap(controller.suggestions.first { $0.text == "0541236789" })
        controller.personal.forget("0541236789", in: .hebrew)
        controller.apply(offer)
        XCTAssertEqual(target.text, "054")
    }

    func testUnavailableTailCannotOfferPhoneThroughOrdinarySuggestions() {
        let target = CursorTextTarget(before: "054")
        target.afterContextIsAvailable = false
        let controller = KeyboardController(target: target, language: .hebrew)
        controller.personal.recordPhoneNumber("0541236789", language: .hebrew, permitted: true)
        controller.refreshSuggestions()
        XCTAssertFalse(controller.suggestions.contains { $0.text == "0541236789" })
        controller.apply(
            Suggestion(
                text: "0541236789", language: .hebrew, commit: .verbatimToken(expected: "054")))
        XCTAssertEqual(target.document, "054")
    }

    func testPartialDeletionOfPhonePrefixRollsBack() {
        let target = CursorTextTarget(before: "call +972 54")
        let controller = KeyboardController(target: target, language: .english)
        controller.personal.recordPhoneNumber("+972 54 123 6789", language: .hebrew, permitted: true)
        target.backwardDeleteLimit = 2
        controller.apply(
            Suggestion(
                text: "+972 54 123 6789", language: .english, commit: .verbatimToken(expected: "+972 54")))
        XCTAssertEqual(target.document, "call +972 54")
    }
}
