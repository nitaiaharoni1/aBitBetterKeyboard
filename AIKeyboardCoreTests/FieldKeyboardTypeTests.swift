import UIKit
import XCTest

@testable import AIKeyboardCore

/// The keyboard shapes itself for the field it is standing over.
///
/// **Every assertion here rejects the shipped build, and the shipped build is
/// simple to state: nothing in this project read `keyboardType` at all.** So the
/// unfixed answer to every one of these cases is "`plane` is still `.letters` and
/// `language` is still whatever the last keystroke left" — a full letter QWERTY
/// over an OTP box, and Hebrew letters in an email field. Each test names the
/// value that build produces beside the one it asserts. The three controls at the
/// bottom are labelled as controls: they pass against the unfixed build on
/// purpose, because what they reject is an over-eager fix. Everything else in
/// the `Controls` section is *not* one — `testAHebrewOnlyKeyboardIsNotForcedIntoALanguageItDoesNotHave`
/// starts from a numeric field, so its plane assertion rejects the unfixed build
/// like the rest.
@MainActor
final class FieldKeyboardTypeTests: XCTestCase {

    private var saved = TypingSettings.snapshot()

    override func setUp() {
        super.setUp()
        saved = TypingSettings.snapshot()
        SharedStore.shared.enabledLanguages = [.english, .hebrew]
    }

    override func tearDown() {
        saved.restore()
        super.tearDown()
    }

    /// A controller standing over a field that has not been declared yet, so the
    /// appearance below is the moment the trait is first read.
    private func keyboard(
        language: KeyboardLanguage = .english, text: String = ""
    ) -> (KeyboardController, MockTextTarget) {
        let target = MockTextTarget(text: text)
        return (KeyboardController(target: target, language: language), target)
    }

    // MARK: NIT-9 — numeric fields

    /// The whole of NIT-9 in one case. iOS substitutes its own keyboard for
    /// `.phonePad` and `.namePhonePad` and for nothing else, so a `.numberPad`
    /// field drew our letters: the unfixed build leaves `plane == .letters` here,
    /// which is what a user reads as "this keyboard is broken".
    func testANumberPadFieldOpensOnTheNumbersPlane() {
        let (controller, target) = keyboard()
        target.keyboardType = .numberPad

        controller.prepareForNewDocument()

        XCTAssertEqual(
            controller.plane, .numbers,
            "an OTP box came up on the letters, which is what shipped")
    }

    /// The other three, including `.numbersAndPunctuation`. A fix that handled
    /// only `.numberPad` — the one everybody names — leaves a price field and a
    /// PIN entry on the letters, and the unfixed build leaves all four there.
    func testEveryNumericFieldTypeOpensOnTheNumbersPlane() {
        for type in [
            UIKeyboardType.numberPad, .decimalPad, .asciiCapableNumberPad, .numbersAndPunctuation
        ] {
            let (controller, target) = keyboard()
            target.keyboardType = type

            controller.prepareForNewDocument()

            XCTAssertEqual(
                controller.plane, .numbers, "\(type) came up on the letter keys")
            XCTAssertEqual(
                controller.language, .english,
                "\(type) moved the language, which is not what a numeric field asked for")
        }
    }

    // MARK: NIT-10 — fields that can only hold ASCII

    /// The whole of NIT-10. `IsASCIICapable` is `true` now, so iOS hands us the
    /// email and URL fields it used to withhold — and the unfixed build answers
    /// them with `language == .hebrew`, which is a field that cannot accept a
    /// single character the user can see on the keys.
    func testAnEmailFieldOnAHebrewKeyboardComesUpOnLatinLetters() {
        let (controller, target) = keyboard(language: .hebrew)
        target.keyboardType = .emailAddress

        controller.prepareForNewDocument()

        XCTAssertEqual(controller.language, .english, "the email field got Hebrew keys")
        XCTAssertEqual(controller.plane, .letters)
        XCTAssertEqual(
            controller.hostLanguage, .english,
            "the host was still told Hebrew, so the field would lay out right to left")
    }

    /// The remaining Latin-wanting types, and `.URL` is the one the unfixed
    /// build hurts most: a Hebrew keyboard cannot type a single character of a
    /// URL. All three leave `language == .hebrew` before this change.
    ///
    /// **`.webSearch` was in this list and contradicted
    /// `testASearchFieldLeavesAHebrewKeyboardAlone` two screens down**, so one of
    /// the two had to be failing on committed `main` whatever the code did. The
    /// search test is the one that matches the shipped decision: `latinFieldTypes`
    /// deliberately excludes `.webSearch`, and `.claude/rules/keyboard-wiring.md`
    /// records why (Apple documents it as taking any script, and Apple's own
    /// Hebrew keyboard stays Hebrew on one, so treating a search box as ASCII
    /// takes the keyboard away in the user's own language for no reason). This
    /// list was asserting the behaviour that decision rejected. Found by NIT-92,
    /// which exists because nobody knew what the suite reported.
    func testEveryLatinWantingFieldTypeMovesOffHebrew() {
        for type in [UIKeyboardType.asciiCapable, .emailAddress, .URL] {
            let (controller, target) = keyboard(language: .hebrew)
            target.keyboardType = type

            controller.prepareForNewDocument()

            XCTAssertEqual(controller.language, .english, "\(type) kept the Hebrew keys")
        }
    }

    /// A form is a run of fields, and the previous one may have been a quantity
    /// box. The email field then needs the *plane* back as well as the language,
    /// and the language half alone would leave it on the digits — which is the
    /// half a fix aimed only at NIT-10 would write.
    func testAnEmailFieldAfterANumericOneGetsTheLettersBack() {
        let (controller, target) = keyboard()
        target.keyboardType = .numberPad
        controller.prepareForNewDocument()
        XCTAssertEqual(controller.plane, .numbers)

        target.keyboardType = .emailAddress
        controller.prepareForNewDocument()

        XCTAssertEqual(
            controller.plane, .letters, "the email field inherited the quantity field's digits")
    }

    // MARK: Putting the shape back

    /// **The shape imposed for one field must come off when the next one does not
    /// want it, and the first version of this fix had no route back at all.**
    /// `plane` is written in three places in the whole project, and the only one
    /// that restores `.letters` is the `123` key, so a build that reshapes without
    /// undoing leaves a chat box drawing digits: six-digit code in one app, switch
    /// to WhatsApp, tap the message field, numeric keyboard, no key pressed in
    /// between. This is the commoner pair than the email case above, because
    /// almost every field on the phone is `.default`.
    func testAnOrdinaryFieldAfterANumericOneGetsTheLettersBack() {
        let (controller, target) = keyboard()
        target.keyboardType = .numberPad
        controller.prepareForNewDocument()
        XCTAssertEqual(controller.plane, .numbers)

        target.keyboardType = .default
        controller.prepareForNewDocument()

        XCTAssertEqual(
            controller.plane, .letters,
            "an ordinary text field inherited the code box's digits")
    }

    /// The language half of the same defect, and the worse one, because it
    /// outlives the app. One extension instance is reused across fields *and*
    /// across host apps, so a Hebrew user who touched one email box kept an
    /// English keyboard in the chat they went back to and in everything after
    /// that, sliding the space bar by hand every time.
    func testLeavingAnEmailFieldGivesTheHebrewKeyboardBack() {
        let (controller, target) = keyboard(language: .hebrew)
        target.keyboardType = .emailAddress
        controller.prepareForNewDocument()
        XCTAssertEqual(controller.language, .english, "the email field did not get Latin keys")

        target.keyboardType = .default
        controller.prepareForNewDocument()

        XCTAssertEqual(
            controller.language, .hebrew,
            "the keyboard kept the English it imposed for the email field")
    }

    /// A run of ASCII fields restores what the user had when they reached the
    /// *first* of them, not what the previous one left. Rejects a fix that stashes
    /// the language on every Latin field and so ends up stashing English.
    func testARunOfLatinFieldsRestoresTheLanguageFromBeforeTheRun() {
        let (controller, target) = keyboard(language: .hebrew)
        for type in [UIKeyboardType.emailAddress, .URL, .asciiCapable] {
            target.keyboardType = type
            controller.prepareForNewDocument()
            XCTAssertEqual(controller.language, .english, "\(type) kept the Hebrew keys")
        }

        target.keyboardType = .default
        controller.prepareForNewDocument()

        XCTAssertEqual(
            controller.language, .hebrew, "a run of ASCII fields stranded the user on English")
    }

    /// The restore is claim-checked, not trusted: a user who slid the space bar
    /// themselves inside the email field has made a decision, and leaving must not
    /// undo it. Rejects a fix that restores unconditionally.
    func testAHandPickedLanguageInsideAnAsciiFieldIsNotUndoneOnLeaving() {
        let (controller, target) = keyboard(language: .hebrew)
        target.keyboardType = .emailAddress
        controller.prepareForNewDocument()
        XCTAssertEqual(controller.language, .english)

        controller.stepLanguage(by: 1)
        XCTAssertEqual(controller.language, .hebrew)

        target.keyboardType = .default
        controller.prepareForNewDocument()

        XCTAssertEqual(
            controller.language, .hebrew,
            "leaving the field overruled the language the user had picked by hand")
    }

    /// **`.webSearch` is not an ASCII field**, whatever the first version of this
    /// said. Apple documents it as optimised for search terms and URL entry, it
    /// accepts any script, and Apple's own Hebrew keyboard stays Hebrew on one.
    /// Searching in Hebrew is ordinary, so taking the keys away is the keyboard
    /// being wrong in the user's own language.
    func testASearchFieldLeavesAHebrewKeyboardAlone() {
        let (controller, target) = keyboard(language: .hebrew)
        target.keyboardType = .webSearch
        controller.prepareForNewDocument()

        XCTAssertEqual(
            controller.language, .hebrew, "a search box took the Hebrew keyboard away")
    }

    /// An address is never capitalised. Before `IsASCIICapable` was corrected iOS
    /// withheld these fields, so the flip is what exposed it — the build this was
    /// written against typed `Nitai@example.com`.
    ///
    /// **It now declares the trait, and that is the point of the extra line.**
    /// This used to pass on `keyboardType` alone, because `.emailAddress` and
    /// `.URL` were special-cased into `shift = .off` while
    /// `autocapitalizationType` was read nowhere in the project. `NIT-89`
    /// replaced that patch with the real trait, and an undeclared trait now means
    /// `.sentences` so that no existing field regresses — which is exactly what
    /// `MockTextTarget` answers. So a host that says nothing arms shift, and it is
    /// the host declaring `.none` that does not. The email field in front of a
    /// real user declares it; this one has to say so too, or it is asserting the
    /// old heuristic under a new name. `AutocapitalizationTests` owns the trait's
    /// own behaviour.
    func testAnEmailFieldDoesNotArriveWithShiftArmed() {
        let (controller, target) = keyboard()
        XCTAssertEqual(controller.shift, .on, "shift no longer starts armed, so this proves nothing")

        target.keyboardType = .emailAddress
        target.autocapitalizationType = UITextAutocapitalizationType.none
        controller.prepareForNewDocument()

        XCTAssertEqual(controller.shift, .off, "the email field capitalised the address")
    }

    // MARK: Decided once, and never taken back

    /// **The rule both tickets are written under: pick at focus, never again.**
    /// `refreshSuggestions` is what a keystroke and a caret tap both reach, so a
    /// fix that re-decided there would put the digits back under a user who had
    /// deliberately pressed ABC — a keyboard that cannot be argued with. The first
    /// assertion is what rejects the unfixed build; the last is what rejects that
    /// over-eager fix.
    func testLeavingTheNumbersPlaneSticks() {
        let (controller, target) = keyboard()
        target.keyboardType = .numberPad
        controller.prepareForNewDocument()
        XCTAssertEqual(controller.plane, .numbers)

        controller.press(.plane(.letters, label: "ABC"))
        XCTAssertEqual(controller.plane, .letters)

        controller.refreshSuggestions()
        controller.refreshSuggestions()

        XCTAssertEqual(
            controller.plane, .letters, "typing put the user back on the digits they had left")
    }

    /// The same rule for the language half: a user who slides the space bar to
    /// Hebrew inside an ASCII-capable search box has said what they want, and the
    /// next keystroke must not undo it.
    func testSlidingBackToHebrewInAnAsciiFieldSticks() {
        let (controller, target) = keyboard(language: .hebrew)
        target.keyboardType = .asciiCapable
        controller.prepareForNewDocument()
        XCTAssertEqual(controller.language, .english)

        controller.stepLanguage(by: 1)
        XCTAssertEqual(controller.language, .hebrew)

        controller.refreshSuggestions()

        XCTAssertEqual(
            controller.language, .hebrew, "typing dragged the user back off the language they chose")
    }

    /// **A field swap with the keyboard still up, which `viewWillAppear` never
    /// hears about.** `textDidChange` / `selectionDidChange` are the only news of
    /// it, and both go through `refreshSuggestions`. The unfixed build fails the
    /// first assertion; a fix that only ever decided on appearance passes that one
    /// and fails the last, leaving the quantity field showing an email keyboard.
    func testMovingToAnotherFieldWithoutDismissingRedecides() {
        let (controller, target) = keyboard(language: .hebrew)
        target.keyboardType = .emailAddress
        controller.prepareForNewDocument()
        XCTAssertEqual(controller.language, .english)

        target.keyboardType = .numberPad
        controller.refreshSuggestions()

        XCTAssertEqual(
            controller.plane, .numbers,
            "focus moved to a quantity field and the keyboard did not notice")
    }

    /// **A nil arriving mid-session is a vanished proxy, not a field that changed
    /// its mind.** `ProxyTextTarget` resolves through a `weak` input view
    /// controller and answers nil when it has gone, so recording that nil as an
    /// adoption would make the *next* callback see `.numberPad` as new and put the
    /// user back on the digits they had just left. That is the last assertion, and
    /// it is a build that reads the trait but records the silence — the obvious
    /// first version of this fix.
    func testAVanishedProxyIsNotAFieldChange() {
        let (controller, target) = keyboard()
        target.keyboardType = .numberPad
        controller.prepareForNewDocument()
        XCTAssertEqual(controller.plane, .numbers)

        controller.press(.plane(.letters, label: "ABC"))
        target.keyboardType = nil
        controller.refreshSuggestions()
        XCTAssertEqual(controller.plane, .letters, "a silent host re-shaped the keyboard")

        target.keyboardType = .numberPad
        controller.refreshSuggestions()

        XCTAssertEqual(
            controller.plane, .letters,
            "the silence counted as an adoption, so the same field read as a new one")
    }

    // MARK: Controls
    //
    // Both pass against the unfixed build on purpose. What they reject is a fix
    // that reaches further than the two tickets do.

    /// An ordinary field is left exactly as it was. A fix that forced Latin or the
    /// numbers plane on `.default` would take a Hebrew keyboard away from every
    /// chat app on the phone.
    func testAnOrdinaryFieldIsLeftAlone() {
        let (controller, target) = keyboard(language: .hebrew)
        target.keyboardType = .default

        controller.prepareForNewDocument()

        XCTAssertEqual(controller.language, .hebrew)
        XCTAssertEqual(controller.plane, .letters)
    }

    /// A host that never implemented the trait is the same silence, and it is the
    /// commonest one: `UITextInputTraits` declares `keyboardType` optional.
    func testAHostThatDeclaresNothingIsLeftAlone() {
        let (controller, target) = keyboard(language: .hebrew)
        target.keyboardType = nil

        controller.prepareForNewDocument()

        XCTAssertEqual(controller.language, .hebrew)
        XCTAssertEqual(controller.plane, .letters)
    }

    /// **Nobody is stranded in a language they have not enabled.** A user with
    /// Hebrew alone has no Latin keyboard to be moved to, and forcing English
    /// would hand them a layout the space bar cannot get them off. The plane half
    /// still runs, which is what rejects the unfixed build here.
    func testAHebrewOnlyKeyboardIsNotForcedIntoALanguageItDoesNotHave() {
        SharedStore.shared.enabledLanguages = [.hebrew]
        let (controller, target) = keyboard(language: .hebrew)
        target.keyboardType = .numberPad
        controller.prepareForNewDocument()
        XCTAssertEqual(controller.plane, .numbers)

        target.keyboardType = .emailAddress
        controller.prepareForNewDocument()

        XCTAssertEqual(
            controller.language, .hebrew,
            "the keyboard switched to a language this user has not enabled")
        XCTAssertEqual(controller.plane, .letters)
    }

    /// **Characterisation, not a defect: `.decimalPad`'s separator is scoped
    /// out.** A locale that writes 1,5 and one that writes 1.5 want different
    /// caps, and this keyboard draws one numbers plane shared by all sixty-four
    /// languages — so ordering it per locale would move the keys under every user,
    /// not only the ones in a price field. Both marks are already on the plane
    /// this fix opens (the full stop twice, in fact: the punctuation row and the
    /// bottom row), so nobody is blocked. This passes against the unfixed build
    /// and exists to fail if a future edit takes one of them away.
    func testBothDecimalSeparatorsAreOnTheNumbersPlane() {
        let keys = KeyboardLayout.rows(for: .english, plane: .numbers).flatMap(\.keys)
        XCTAssertTrue(keys.contains { $0.cap == .character(".") }, "no full stop on the numbers plane")
        XCTAssertTrue(keys.contains { $0.cap == .character(",") }, "no comma on the numbers plane")
    }
}
