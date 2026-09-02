import UIKit
import XCTest

@testable import AIKeyboardCore

/// NIT-89: the keyboard now reads `autocapitalizationType`, the same way
/// `FieldKeyboardTypeTests` proved it reads `keyboardType`.
///
/// **Every assertion here rejects the shipped build, and the shipped build is
/// simple to state: `shift` starts `.on`, Return and the double-space full stop
/// re-arm it to `store.storedAutocapitalise ? .on : .off` unconditionally, and
/// nothing else ever touches it.** So the unfixed answer to every case below is
/// "shift behaves exactly as if the field were an ordinary `.sentences` field,
/// whatever it actually declared" — a login field types a capitalised address,
/// a `.words` field never capitalises past its first letter, an `.allCharacters`
/// field never locks, and a caps lock the user set by hand gets cancelled by
/// the next Return. Each test names the value the unfixed build produces beside
/// the one it asserts.
@MainActor
final class AutocapitalizationTests: XCTestCase {

    private var savedAutocapitalise = true

    override func setUp() {
        super.setUp()
        savedAutocapitalise = SharedStore.shared.autocapitalise
        SharedStore.shared.autocapitalise = true
    }

    override func tearDown() {
        SharedStore.shared.autocapitalise = savedAutocapitalise
        super.tearDown()
    }

    /// A controller standing over a field that has not been declared yet, so
    /// the appearance below is the moment the trait is first read.
    private func keyboard(text: String = "") -> (KeyboardController, MockTextTarget) {
        let target = MockTextTarget(text: text)
        return (KeyboardController(target: target, language: .english), target)
    }

    // MARK: `.none` never arms shift

    /// **The whole of NIT-89's own example, by Return.** A user ends a sentence
    /// (armed by Return) and then taps a login field declaring `.none`. The
    /// unfixed build leaves the sentence's arm standing, so the next letter
    /// typed into the login field is capitalised — `Nitai`, not `nitai`.
    func testEndingASentenceThenReturningDoesNotCapitalizeANoneField() {
        let (controller, target) = keyboard()
        controller.prepareForNewDocument()
        for character in "hi" { controller.press(.character(String(character))) }
        controller.press(.ret)

        target.autocapitalizationType = UITextAutocapitalizationType.none
        controller.prepareForNewDocument()
        controller.press(.character("n"))

        XCTAssertEqual(
            target.text, "Hi\nn",
            "a none field capitalised a letter the way the sentence before it would have")
    }

    /// **The same example, by the double-space full stop.** `insertSpace`'s
    /// double-tap branch is the second site NIT-89 names; the unfixed build
    /// arms shift there too, and just as unconditionally.
    func testEndingASentenceWithADoubleSpaceDoesNotCapitalizeANoneField() {
        let (controller, target) = keyboard()
        controller.prepareForNewDocument()
        for character in "hi" { controller.press(.character(String(character))) }
        controller.press(.space)
        controller.press(.space)
        XCTAssertEqual(target.text, "Hi. ", "the double space did not become a full stop")

        target.autocapitalizationType = UITextAutocapitalizationType.none
        controller.prepareForNewDocument()
        controller.press(.character("n"))

        XCTAssertEqual(
            target.text, "Hi. n",
            "a none field capitalised a letter the way the sentence before it would have")
    }

    // MARK: `.words` capitalises each word

    /// **The other half of NIT-89's "done when."** The unfixed build has no
    /// concept of a word boundary arming shift at all — only Return and the
    /// double-space full stop ever touch it — so the second word here comes
    /// back lowercase on the shipped build even though the first happens to be
    /// capitalised by the keyboard's own construction-time default.
    func testAWordsFieldCapitalisesEachWord() {
        let (controller, target) = keyboard()
        target.autocapitalizationType = .words
        controller.prepareForNewDocument()

        for character in "ab" { controller.press(.character(String(character))) }
        controller.press(.space)
        for character in "cd" { controller.press(.character(String(character))) }

        XCTAssertEqual(target.text, "Ab Cd", "a words field stopped capitalising after the first word")
    }

    /// The global switch is still the master control: NIT-89 adds a boundary
    /// this keyboard arms shift at, and that boundary has to ask the same
    /// question Return and the double-space full stop already ask.
    func testAWordsFieldRespectsAutocapitaliseTurnedOff() {
        SharedStore.shared.autocapitalise = false

        let (controller, target) = keyboard()
        target.autocapitalizationType = .words
        controller.prepareForNewDocument()
        XCTAssertEqual(
            controller.shift, .off,
            "a words field armed shift even with Auto-Capitalise off")

        for character in "ab" { controller.press(.character(String(character))) }
        controller.press(.space)
        for character in "cd" { controller.press(.character(String(character))) }

        XCTAssertEqual(target.text, "ab cd", "a words field capitalised with the global switch off")
    }

    // MARK: `.allCharacters` locks shift

    /// The unfixed build never locks shift automatically at all — `.locked` is
    /// reachable only through three taps of the shift key — so a caps-lock
    /// field types only its first letter capitalised on the shipped build.
    func testAnAllCharactersFieldLocksShiftAndCapitalisesEveryLetter() {
        let (controller, target) = keyboard()
        target.autocapitalizationType = .allCharacters
        controller.prepareForNewDocument()
        XCTAssertEqual(controller.shift, .locked, "an all-characters field did not lock shift")

        for character in "ab" { controller.press(.character(String(character))) }
        controller.press(.space)
        for character in "cd" { controller.press(.character(String(character))) }

        XCTAssertEqual(target.text, "AB CD", "an all-characters field let a lowercase letter through")
    }

    // MARK: The nil fallback, spelled out

    /// **A host that never implements the trait must see no change**, which is
    /// the same guarantee `keyboardType`'s nil fallback gives. This exercises
    /// all three boundaries against it in one field: the initial arm, an
    /// ordinary space that must *not* arm, and Return that must.
    func testAHostThatNeverImplementsTheTraitBehavesAsSentences() {
        let (controller, target) = keyboard()
        target.autocapitalizationType = nil
        controller.shift = .off
        controller.prepareForNewDocument()
        XCTAssertEqual(controller.shift, .on, "a nil trait did not arm shift the way `.sentences` does")

        controller.press(.character("h"))
        controller.press(.space)
        controller.press(.character("i"))
        XCTAssertEqual(target.text, "H i", "a nil trait behaved like `.words` instead of `.sentences`")

        controller.press(.ret)
        controller.press(.character("t"))
        XCTAssertEqual(target.text, "H i\nT", "a nil trait stopped re-arming shift after Return")
    }

    // MARK: Care needed — shift is the user's own control too

    /// **The concrete shape of "do not fight them mid-field."** A user who has
    /// locked caps by hand is not asking this keyboard's own idea of a sentence
    /// boundary to cancel it. The unfixed build's Return unconditionally writes
    /// `store.storedAutocapitalise ? .on : .off`, so it cancels a hand-set caps
    /// lock exactly the way it would arm an ordinary sentence.
    func testAUserLockedCapsSurvivesReturn() {
        let (controller, _) = keyboard()
        controller.prepareForNewDocument()
        controller.press(.character("h"))

        controller.toggleShift()
        controller.toggleShift()
        XCTAssertEqual(controller.shift, .locked, "two taps did not reach caps lock, so this proves nothing")

        controller.press(.ret)

        XCTAssertEqual(controller.shift, .locked, "Return cancelled a caps lock the user set by hand")
    }

    // MARK: Where the caret is, not only what the field declared

    /// **The measured defect.** Reopening a half-written message put the caret
    /// mid-word, and the unfixed build armed shift there anyway — `shift` starts
    /// `.on` and `adoptFieldAutocapitalization` re-armed it at focus without ever
    /// asking where the caret was — so the very next letter came back capitalised:
    /// `hey how are yoU`. Nothing but a typed character lowers the arm, so a word
    /// the user did not type in this session keeps it standing indefinitely; that
    /// is also the whole of `PendingAutocorrectClaimTests
    /// .testImmediateAutocorrectUndoDiscardsTheStagedLearning`'s `heloW`.
    func testAFieldFocusedMidWordDoesNotCapitaliseTheNextLetter() {
        let (controller, target) = keyboard(text: "hey how are yo")
        controller.prepareForNewDocument()

        controller.press(.character("u"))

        XCTAssertEqual(
            target.text, "hey how are you",
            "a caret sitting mid-word armed shift and capitalised the letter that "
                + "finished the word")
    }

    /// **The control, and it is what a fix that simply stopped arming fails.**
    /// The same field, the same focus, with the caret where a sentence genuinely
    /// begins.
    func testAFieldFocusedAfterAFullStopStillCapitalises() {
        let (controller, target) = keyboard(text: "Hey. ")
        controller.prepareForNewDocument()

        controller.press(.character("h"))

        XCTAssertEqual(
            target.text, "Hey. H",
            "a caret after a finished sentence stopped arming shift")
    }

    /// The second control: the ordinary case this keyboard has always got right.
    func testAnEmptyFieldFocusedStillCapitalisesTheFirstLetter() {
        let (controller, target) = keyboard()
        controller.prepareForNewDocument()

        controller.press(.character("h"))

        XCTAssertEqual(target.text, "H", "an empty field stopped arming shift")
    }

    /// A `.words` field asks a different question of the same caret: every word
    /// starts capitalised, so the boundary is a word rather than a sentence.
    /// Mid-word is still mid-word, and the control is the space in front of the
    /// next one.
    func testAWordsFieldFocusedMidWordDoesNotCapitaliseButFocusedAtAGapDoes() {
        let (controller, target) = keyboard(text: "Hey Yo")
        target.autocapitalizationType = .words
        controller.prepareForNewDocument()
        controller.press(.character("u"))
        XCTAssertEqual(
            target.text, "Hey You",
            "a words field capitalised a letter in the middle of a word")

        let (other, otherTarget) = keyboard(text: "Hey ")
        otherTarget.autocapitalizationType = .words
        other.prepareForNewDocument()
        other.press(.character("y"))
        XCTAssertEqual(
            otherTarget.text, "Hey Y",
            "a words field stopped capitalising the word after a space")
    }

    /// **Construction is the second place that arms with no key pressed**, and it
    /// is the one the autocorrect-undo defect came through: a controller built
    /// over a document it did not type carries `shift == .on` until the first
    /// character, whatever the caret is standing on. Both halves, so a build that
    /// simply started `.off` fails the first.
    func testAControllerBuiltOverADocumentDecidesShiftFromTheCaret() {
        let (armed, _) = keyboard()
        XCTAssertEqual(armed.shift, .on, "a controller built over an empty field did not arm shift")

        let (unarmed, _) = keyboard(text: "helo")
        XCTAssertEqual(
            unarmed.shift, .off,
            "a controller built with the caret mid-word armed shift for the next letter")
    }

    // MARK: Decided once, and never taken back

    /// **The mode is read at focus and not re-read from a keystroke.** A host
    /// that silently changes what it reports mid-field — without the keyboard
    /// ever losing focus and coming back — must not change how typing behaves,
    /// the same rule `adoptFieldKeyboardType` already holds for `keyboardType`.
    func testTheModeIsNotReReadWithoutAFreshFocus() {
        let (controller, target) = keyboard()
        target.autocapitalizationType = .words
        controller.prepareForNewDocument()

        controller.press(.character("a"))
        controller.press(.space)
        controller.press(.character("b"))
        XCTAssertEqual(target.text, "A B", "a words field is not capitalising each word")

        // No `prepareForNewDocument()` call between here and the next press:
        // this is not a new focus, so the mode decided above must still govern.
        target.autocapitalizationType = UITextAutocapitalizationType.none
        controller.press(.space)
        controller.press(.character("c"))

        XCTAssertEqual(
            target.text, "A B C",
            "typing after the trait changed mid-field stopped following the mode decided at focus")
    }
}
