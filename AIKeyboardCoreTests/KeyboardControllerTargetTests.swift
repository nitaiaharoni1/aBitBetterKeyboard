import UIKit
import XCTest

@testable import AIKeyboardCore

/// The keyboard typed nothing on a real device, and this is the test that was
/// missing.
///
/// **What happened.** `KeyboardController.target` was `weak`, and the extension's
/// only caller passed a target it built inline:
///
/// ```swift
/// controller = KeyboardController(target: ProxyTextTarget(textDocumentProxy), …)
/// ```
///
/// Nothing else retained that `ProxyTextTarget`, so it was deallocated as
/// `viewDidLoad` returned. From then on every mutation in the controller was
/// `target?.insertText(…)` against nil — a no-op that raises no error, logs
/// nothing and looks identical to a working keyboard from the inside. The keys
/// pressed, the shimmer ran, the suggestion bar drew, and not one character
/// reached the host app.
///
/// **Why nothing caught it.** Every existing test, and the in-app playground,
/// passes a `MockTextTarget` that something else holds for the duration — a
/// `@StateObject` in `KeyboardPreview`, a local in a test. A local in a test is
/// the important half: an `XCTestCase` method's local lives to the end of the
/// method, so the weak reference stayed valid for exactly as long as the
/// assertion needed and the suite was green against a keyboard that could not
/// type. The tests below take the target *out of scope* before asserting, which
/// is the only shape that can tell a held reference from a lucky one.
@MainActor
final class KeyboardControllerTargetTests: XCTestCase {

    /// The one that fails against the shipped bug.
    func testTheControllerHoldsItsTargetAfterTheCallerLetsGo() {
        weak var observer: MockTextTarget?
        let controller: KeyboardController

        do {
            let target = MockTextTarget()
            observer = target
            controller = KeyboardController(target: target)
        }

        XCTAssertNotNil(
            observer,
            """
            The controller dropped its text target as soon as the caller let go. \
            On a device this is a keyboard that draws and clicks and inserts \
            nothing, because the extension builds its ProxyTextTarget inline.
            """)

        controller.press(.character("h"))
        controller.press(.character("i"))

        XCTAssertEqual(observer?.text, "Hi", "Keystrokes did not reach the document")
    }

    /// The same thing said the other way round: the extension's exact call shape.
    /// If this compiles and passes, an inline target survives its own statement.
    ///
    /// **The letter is lowercase and that is not this test's subject.** The seed
    /// puts the caret in the middle of a sentence, and a controller built over a
    /// document only arms shift where a sentence begins — see
    /// `caretBeginsACapitalizedRun`. What rejects the dropped-target build is the
    /// seed coming back at all: a released target reads an empty `contextBefore`,
    /// so the answer there is `""`, not `"seed x"`.
    func testATargetBuiltInsideTheInitialiserCallSurvives() {
        let controller = KeyboardController(target: MockTextTarget(text: "seed "))
        controller.press(.character("x"))

        XCTAssertEqual(
            controller.contextBefore, "seed x",
            "A target constructed in argument position was released before the first keystroke")
    }

    /// `attach` is the app's path and had the same hole.
    func testAttachHoldsTheNewTarget() {
        let controller = KeyboardController(target: MockTextTarget())
        weak var observer: MockTextTarget?

        do {
            let replacement = MockTextTarget(text: "second ")
            observer = replacement
            controller.attach(target: replacement)
        }

        XCTAssertNotNil(observer, "attach(target:) did not hold what it was handed")
        controller.press(.character("y"))
        XCTAssertEqual(observer?.text, "second Y")
    }

    /// Suggestions read the document through the same reference, so the dropped
    /// target broke autocomplete in exactly the same silent way — an empty
    /// `contextBefore` looks like an empty field, and an empty field has nothing
    /// to complete.
    ///
    /// **This asserts on content, and the first draft asserting non-emptiness was
    /// worthless.** A nil target makes `currentWordPrefix` empty, which sends
    /// `SuggestionEngine` down its empty-prefix branch, which returns the
    /// hardcoded `["I", "The", "We"]` — three items, so "not empty" was true of
    /// the broken keyboard too. That is not a hypothetical about the test: it is
    /// what the phone actually showed. The bar never went blank, it sat on
    /// `I / The / We` forever while the document underneath was unreadable, which
    /// is precisely what defect D2 reported. `SuggestionEngineTests` pins that
    /// same triple for an empty prefix, so the two files agreed with each other
    /// and with nothing on the device.
    func testSuggestionsSeeTheDocumentAfterTheCallerLetsGo() {
        let controller: KeyboardController
        do {
            controller = KeyboardController(target: MockTextTarget(text: "hel"))
        }
        controller.refreshSuggestions()

        // The echo is excluded. `SuggestionEngine` unconditionally offers the
        // literal keystrokes as candidate zero so the user can never be trapped
        // in a word they did not type — which means `hasPrefix("hel")` is true of
        // *any* build that reads the document at all, including one whose
        // completion lookup is broken. Only a word the engine had to generate
        // counts. `SuggestionEngineTests` pins that "hello" is one of them.
        XCTAssertTrue(
            controller.suggestions.contains {
                let text = $0.text.lowercased()
                return text != "hel" && text.hasPrefix("hel")
            },
            """
            No generated candidate continues "hel" — the engine was asked about an \
            empty document and answered with its no-context defaults \
            \(controller.suggestions.map(\.text)).
            """)
    }

    // MARK: The resolving initialiser

    /// `textDocumentProxy` is replaced when the host changes the focused field, so
    /// the target asks for it per call rather than keeping the first one. Proved
    /// with a stand-in that counts, since a real proxy swap needs a host app.
    func testTheResolvingInitialiserAsksEveryTime() {
        final class CountingProxy: NSObject, UITextDocumentProxy {
            var documentContextBeforeInput: String?
            var documentContextAfterInput: String?
            var selectedText: String?
            var documentInputMode: UITextInputMode?
            var documentIdentifier = UUID()
            func adjustTextPosition(byCharacterOffset offset: Int) {}
            func setMarkedText(_ markedText: String, selectedRange: NSRange) {}
            func unmarkText() {}
            var hasText: Bool { false }
            func insertText(_ text: String) {}
            func deleteBackward() {}

            /// A positive `false`, not silence. Without this the stub declines to
            /// answer whether it is secure, `isSecureTextEntry` is nil whether the
            /// resolver is alive or dead, and the assertion at the end of this
            /// test cannot tell the two apart — which is the same true-by-
            /// construction defect that got past two earlier rounds of review.
            ///
            /// `@objc` is load-bearing and its absence is invisible.
            /// `isSecureTextEntry` is an `@optional` member of the ObjC protocol
            /// `UITextInputTraits`, so it is reached through the existential by
            /// message send. Swift stopped inferring `@objc` for members in
            /// Swift 4, so a plain `var` here compiles, satisfies nothing, and
            /// leaves the property answering nil — which is exactly the silence
            /// this override exists to replace.
            @objc var isSecureTextEntry: Bool { false }
        }

        let first = CountingProxy()
        first.documentContextBeforeInput = "first"
        let second = CountingProxy()
        second.documentContextBeforeInput = "second"

        var current: CountingProxy? = first
        let target = ProxyTextTarget(resolving: { current })

        XCTAssertEqual(target.documentContextBeforeInput, "first")
        current = second
        XCTAssertEqual(
            target.documentContextBeforeInput, "second",
            "The target kept the proxy it saw first, so a field change types into the old field")

        // The host is gone. `KeyView`'s key-repeat task is cancelled from
        // `DragGesture.onEnded`, so a gesture interrupted by teardown can still
        // call in here — which is why the resolver may answer nil and why it is
        // `weak` rather than `unowned`. None of this may trap.
        current = nil
        target.insertText("x")
        target.deleteBackward()
        XCTAssertNil(target.documentContextBeforeInput)

        // And it stops answering rather than answering wrongly. The stub says a
        // positive `false` while it is alive, so this pair genuinely distinguishes
        // the two states: answered → not answered. A vanished host is
        // indistinguishable from a silent one, which is the truth, and
        // `SecureField.answered` being false is what makes a refusal count as
        // `refusedSecureUnknown` — nobody told us — rather than `refusedSecure`,
        // which would claim a host said this was a password field.
        //
        // Note the direction: `permitsRead` *permits* on silence by design (see
        // `SecureField`'s doc comment — iOS swaps in the system keyboard for a
        // secure field, so this branch essentially cannot fire), so the property
        // worth pinning is that the answer is absent, not that the read is
        // refused.
        XCTAssertFalse(
            SecureField.answered(secure: target.isSecureTextEntry),
            "A dead host claimed to know whether the field was secure")
    }

    /// The fixed-proxy initialiser, which the extension does not use and which is
    /// otherwise reachable from nowhere. Kept because a caller holding a proxy
    /// directly has no controller to ask — and pinned here so its doc comment's
    /// claim that tests use it is true rather than aspirational.
    func testTheFixedInitialiserForwardsToTheProxyItWasGiven() {
        final class StubProxy: NSObject, UITextDocumentProxy {
            var documentContextBeforeInput: String? = "before"
            var documentContextAfterInput: String? = "after"
            var selectedText: String? = "picked"
            var documentInputMode: UITextInputMode?
            var documentIdentifier = UUID()
            private(set) var inserted = ""
            private(set) var deletes = 0
            func adjustTextPosition(byCharacterOffset offset: Int) {}
            func setMarkedText(_ markedText: String, selectedRange: NSRange) {}
            func unmarkText() {}
            var hasText: Bool { !inserted.isEmpty }
            func insertText(_ text: String) { inserted += text }
            func deleteBackward() { deletes += 1 }
            /// `@objc` for the same reason as `CountingProxy`'s: without it the
            /// optional protocol member is never satisfied and this reads nil.
            @objc var isSecureTextEntry: Bool { true }
        }

        let proxy = StubProxy()
        let target = ProxyTextTarget(proxy)

        XCTAssertEqual(target.documentContextBeforeInput, "before")
        XCTAssertEqual(target.documentContextAfterInput, "after")
        XCTAssertEqual(target.selectedText, "picked")
        XCTAssertEqual(target.isSecureTextEntry, true)

        target.insertText("ab")
        target.deleteBackward()
        XCTAssertEqual(proxy.inserted, "ab")
        XCTAssertEqual(proxy.deletes, 1)
    }
}
