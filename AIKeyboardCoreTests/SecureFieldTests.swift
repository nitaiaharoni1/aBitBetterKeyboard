import UIKit
import XCTest

@testable import AIKeyboardCore

/// The secure-field guard's whole truth table, including the two rows the naive
/// spelling of it gets wrong.
///
/// The guard takes the two traits rather than a `UITextDocumentProxy`, which is
/// what makes this file possible: every row below is a host that answers a
/// certain way, and none of them needs a host app, a keyboard extension or a
/// device. What it does **not** cover, and cannot, is which of these rows a real
/// host produces — `isSecureTextEntry` is an `@optional` trait and whether any
/// app populates it through the proxy is a device question. That is why a
/// refusal is counted rather than assumed; see `CaptureIntent.refusedSecureUnknown`.
final class SecureFieldTests: XCTestCase {

    // MARK: The rule that matters

    /// **Silence permits, and that is the deliberate answer.** An earlier version
    /// refused on `nil`, reasoning that a guard whose default is "allow" is not a
    /// guard. Two facts overrule it. Apple's App Extension Programming Guide:
    /// *"When a user taps in a secure text input object, the system temporarily
    /// replaces your custom keyboard with the system keyboard"* — so this
    /// keyboard is never on screen for a password field. And `nil` means the host
    /// did not implement an `@optional` protocol member, not that the field is
    /// secret. Refusing on it guards a case the OS already handles and disables
    /// Reply on every silent host in exchange.
    func testAnUnansweredFieldIsPermittedBecauseSilenceIsNotEvidence() {
        XCTAssertTrue(
            SecureField.permitsRead(secure: nil, contentType: nil),
            "nil is an unimplemented optional trait, not a password field")
        XCTAssertFalse(
            SecureField.answered(secure: nil),
            "it still counts as unanswered, which is how R14 stays measurable")
    }

    func testAFieldThatSaysItIsSecureIsRefused() {
        XCTAssertFalse(SecureField.permitsRead(secure: true, contentType: nil))
    }

    /// The only row that permits: a positive `false`.
    func testAFieldThatSaysItIsNotSecureIsPermitted() {
        XCTAssertTrue(SecureField.permitsRead(secure: false, contentType: nil))
    }

    // MARK: The content type is a second refusal and never a permission

    /// Both levels of the double optional are real, and neither is evidence of
    /// safety: the outer nil is a host that never implemented the property, the
    /// inner nil is one that implemented it and set nothing. Both fall through to
    /// whatever `isSecureTextEntry` said.
    func testNeitherKindOfMissingContentTypeChangesTheAnswer() {
        XCTAssertTrue(SecureField.permitsRead(secure: false, contentType: nil))
        XCTAssertTrue(SecureField.permitsRead(secure: false, contentType: .some(.none)))
        XCTAssertTrue(SecureField.permitsRead(secure: nil, contentType: .some(.none)))
        XCTAssertFalse(SecureField.permitsRead(secure: true, contentType: .some(.none)))
    }

    /// A sensitive content type refuses on its own, even when the field has
    /// positively claimed not to be secure. A one-time-code field is often not
    /// `secureTextEntry` at all, because the code is meant to be readable.
    func testASensitiveContentTypeRefusesEvenWhenTheFieldSaysItIsNotSecure() {
        for type in SecureField.sensitive {
            XCTAssertFalse(
                SecureField.permitsRead(secure: false, contentType: .some(type)),
                "\(type.rawValue) is a credential and must refuse on its own")
            XCTAssertFalse(
                SecureField.permitsRead(secure: nil, contentType: .some(type)),
                "\(type.rawValue) must refuse on a silent field too: this is the branch that still bites")
        }
    }

    /// …and an ordinary content type is not a permission either: it never rescues
    /// a field that positively said it was secure.
    func testAnOrdinaryContentTypeIsNotAPermission() {
        XCTAssertTrue(SecureField.permitsRead(secure: false, contentType: .some(.emailAddress)))
        XCTAssertTrue(SecureField.permitsRead(secure: nil, contentType: .some(.emailAddress)))
        XCTAssertFalse(
            SecureField.permitsRead(secure: true, contentType: .some(.emailAddress)),
            "a friendly content type must not rescue a field that said it is secure")
    }

    /// The five constants are `UITextInputTraits.h:305-309` and `:324` of
    /// `iPhoneOS26.2.sdk`. Pinned by count so that widening the list is a
    /// decision somebody makes here rather than a line that slips in: every entry
    /// costs a screen the user asked to have read.
    func testTheSensitiveListIsTheFiveCredentialTypes() {
        XCTAssertEqual(
            SecureField.sensitive,
            [.password, .newPassword, .oneTimeCode, .creditCardNumber, .creditCardSecurityCode])
    }

    // MARK: Which of the two counters a refusal belongs to

    func testARefusalIsAttributedToTheFieldOrToItsSilence() {
        XCTAssertTrue(SecureField.answered(secure: true), "the host said yes: refusedSecure")
        XCTAssertTrue(SecureField.answered(secure: false))
        XCTAssertFalse(SecureField.answered(secure: nil), "nobody said anything: refusedSecureUnknown")
    }

    // MARK: The in-app document

    /// `MockTextTarget` backs the keyboard the app renders in onboarding and the
    /// playground. It answers a positive `false` rather than shrugging, because a
    /// shrug is a refusal under this guard and would switch Reply off inside the
    /// app for a field that is a `String` in this process.
    @MainActor
    func testTheInAppDocumentAnswersRatherThanShrugging() {
        let target = MockTextTarget(text: "hello")

        XCTAssertEqual(target.isSecureTextEntry, false)
        XCTAssertTrue(
            SecureField.permitsRead(secure: target.isSecureTextEntry, contentType: target.textContentType))
    }
}
