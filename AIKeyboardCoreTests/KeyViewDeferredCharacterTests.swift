import SwiftUI
import XCTest

@testable import AIKeyboardCore

/// A character key types on the lift, not on the finger-down (NIT-108).
///
/// **The gesture cannot be driven from here**, the way `AlternatesPopupTests` and
/// `ToneAlternatesTests` both say of the same key, so these measure the two halves
/// a gesture would join: what `KeyView` decides about a key (`defersCharacterToLift`,
/// and whether `KeyboardView` hands it a touch handler at all), and what the
/// controller does with the touch once it is reported
/// (`characterTouch(_:)` and everything under it).
///
/// **What each of these rejects.** The pre-NIT-108 keyboard called
/// `onPress` on finger-down, so `press(.character("a"))` was the whole of a
/// keystroke and the document held `a` before the finger came off the glass.
/// Every assertion below is written against the two builds that could bring that
/// back: one where `beginCharacterTouch` simply forwards to `press`, and one
/// where the wiring in `KeyboardView.characterTouchHandler(for:)` returns nil so
/// the key falls back to the immediate path. Both of those are green against a
/// test that only asks "did an `a` end up in the field", which is why several of
/// these assert on the field *before* the lift as well as after it.
@MainActor
final class KeyViewDeferredCharacterTests: XCTestCase {

    private var saved = TypingSettings.snapshot()
    private var haptics = true

    override func setUp() {
        super.setUp()
        saved = TypingSettings.snapshot()
        haptics = SharedStore.shared.haptics
        // Off, so every assertion below is about *when* a character lands rather
        // than about what the space bar decided to replace it with.
        SharedStore.shared.autocorrect = false
        SharedStore.shared.enabledLanguages = [.english, .hebrew]
    }

    override func tearDown() {
        SharedStore.shared.haptics = haptics
        saved.restore()
        super.tearDown()
    }

    private func controller(_ text: String = "") -> (KeyboardController, MockTextTarget) {
        let target = MockTextTarget(text: text)
        let controller = KeyboardController(target: target, language: .english)
        // `shift` starts `.on` — an empty field arms it at focus — and every
        // assertion below is about a lower-case letter arriving at a moment,
        // not about capitalisation. Same line as `CandidateCommitTests` and
        // `EmojiSearchTypingTests` open with.
        controller.shift = .off
        return (controller, target)
    }

    private func letterSpec(
        _ character: String, in language: KeyboardLanguage = .english
    ) throws
        -> KeySpec
    {
        try XCTUnwrap(
            KeyboardLayout.rows(for: language, plane: .letters)
                .flatMap(\.keys)
                .first { $0.cap == .character(character) },
            "\(language.displayName) has no \(character) key")
    }

    // MARK: A quick tap

    /// The ordinary keystroke, unchanged in everything except the moment it lands.
    func testAQuickTapStillTypesItsLetter() {
        let (controller, target) = controller()

        controller.characterTouch(.began(.character("a"), CGPoint(x: 0.5, y: 0.5)))
        controller.characterTouch(.ended)

        XCTAssertEqual(target.text, "a", "a tap down and up did not type its letter")
        XCTAssertNil(
            controller.pendingCharacter,
            "the key is still holding a character after the finger came off it")
    }

    // MARK: A hold

    /// **The whole of NIT-108, and the one assertion that rejects the shipped
    /// build outright.** Before this change the finger-down *was* the keystroke:
    /// `press(.character("a"))` ran from `DragGesture.onChanged` and `a` was in
    /// the document while the finger was still on the glass — which is what made
    /// the accents popup a delete-and-retype. Asserting the field is still empty
    /// here is what a `beginCharacterTouch` that forwards to `press` fails.
    ///
    /// The second assertion is the other half: nothing is *lost*, it is parked.
    /// A build that simply threw the finger-down away would pass the first
    /// assertion and be a keyboard that types nothing at all.
    func testAHeldKeyTypesNothingWhileTheFingerIsStillDown() {
        let (controller, target) = controller()

        controller.characterTouch(.began(.character("a"), CGPoint(x: 0.5, y: 0.5)))

        XCTAssertEqual(
            target.text, "",
            "the letter was written while the finger was still holding the key")
        XCTAssertNotNil(
            controller.pendingCharacter,
            "the held character was dropped rather than held")
    }

    /// Once, however many ways the touch is reported as over.
    ///
    /// `KeyView.endPress` is idempotent and a normal lift reaches it twice — once
    /// from `onEnded` and once from the gesture state resetting behind it — and a
    /// cancellation can arrive after the lift rather than instead of it, which is
    /// the ordering `SpaceTouchPhase.cancelled` already records. A commit that was
    /// not claim-checked would type `aaa` here.
    func testAHeldKeyTypesExactlyOnceOnRelease() {
        let (controller, target) = controller()

        controller.characterTouch(.began(.character("a"), CGPoint(x: 0.5, y: 0.5)))
        controller.characterTouch(.ended)
        controller.characterTouch(.ended)
        controller.characterTouch(.ended)

        XCTAssertEqual(target.text, "a", "the released key typed its letter more than once")
    }

    /// A hold is not a repeat, and it must not become one.
    ///
    /// Delete is the key that repeats, and it repeats because it does *not* defer:
    /// `KeyView.startRepeatIfNeeded` runs from the same finger-down branch that
    /// this change moved the letters out of, so a backspace that ever started
    /// waiting for its lift would stop repeating altogether. Asserting the pair
    /// is what rejects a build that widened the deferral to every key.
    func testDeleteStillActsOnTheFingerDownSoItCanStillRepeat() throws {
        let view = KeyboardView(controller: controller().0)

        XCTAssertNotNil(
            view.characterTouchHandler(for: try letterSpec("a")),
            "a letter key was not given the touch handler that makes it wait")
        for cap in [KeyCap.backspace, .deleteForward, .shift, .space, .ret, .globe, .dictation] {
            XCTAssertNil(
                view.characterTouchHandler(for: KeySpec(cap)),
                "\(cap) was made to wait for a lift, which stops delete repeating")
        }
    }

    /// The same question asked of the key rather than of the wiring, because the
    /// key is what reads it: `KeyView` falls back to the immediate path whenever
    /// the handler is absent, so a preview or a geometry test does not silently
    /// swallow its keystrokes.
    func testOnlyACharacterKeyWaitsForItsLift() throws {
        func key(_ spec: KeySpec, touch: ((CharacterTouchPhase) -> Void)?) -> KeyView {
            KeyView(
                spec: spec, width: 34, height: 44, language: .english, shift: .off,
                onPress: { _, _ in }, onCharacterTouch: touch)
        }

        XCTAssertTrue(key(try letterSpec("a"), touch: { _ in }).defersCharacterToLift)
        XCTAssertFalse(
            key(try letterSpec("a"), touch: nil).defersCharacterToLift,
            "a key with no handler must keep the immediate path or it types nothing")
        XCTAssertFalse(
            key(KeySpec(.backspace), touch: { _ in }).defersCharacterToLift,
            "delete deferred to its lift and would never start its repeater")
    }

    // MARK: Rollover

    /// **The rollover answer, stated as the assertion before any lift happens.**
    ///
    /// Two thumbs overlap constantly on a phone keyboard, and they do not lift in
    /// the order they land: press `a`, press `b`, lift `b`, lift `a` is an
    /// ordinary thing for a pair of hands to do. A keyboard that waited for each
    /// key's own lift would spell that `ba`. So the *arrival* of the second touch
    /// is what settles the first, which means the field already reads `a` here,
    /// with both fingers still down — and no lift order can change it afterwards.
    func testTheNextFingerDownCommitsTheKeyBeforeIt() {
        let (controller, target) = controller()

        controller.characterTouch(.began(.character("a"), CGPoint(x: 0.5, y: 0.5)))
        controller.characterTouch(.began(.character("b"), CGPoint(x: 0.5, y: 0.5)))

        XCTAssertEqual(
            target.text, "a",
            "the second key went down and the first one had still typed nothing")
    }

    /// The same touches carried through to both lifts. The two `.ended`s arrive in
    /// whatever order the fingers came off, which is exactly why the answer cannot
    /// depend on them: the second is already a no-op.
    func testTwoOverlappingTouchesLandInTheOrderTheKeysWentDown() {
        let (controller, target) = controller()

        controller.characterTouch(.began(.character("a"), CGPoint(x: 0.5, y: 0.5)))
        controller.characterTouch(.began(.character("b"), CGPoint(x: 0.5, y: 0.5)))
        controller.characterTouch(.ended)
        controller.characterTouch(.ended)

        XCTAssertEqual(target.text, "ab", "overlapping touches did not land in down order")
    }

    /// Any key that acts pays the open one, not only another letter. Backspace is
    /// the case worth pinning: it used to arrive after a character that was
    /// already in the field, and it still has to.
    func testAKeyThatIsNotALetterAlsoCommitsTheHeldCharacterFirst() {
        let (controller, target) = controller()

        controller.characterTouch(.began(.character("a"), CGPoint(x: 0.5, y: 0.5)))
        controller.press(.backspace)

        XCTAssertEqual(
            target.text, "",
            "delete ran before the letter it was pressed after, so it ate the wrong character")
    }

    /// An open space bar and an open letter cannot both be outstanding, because a
    /// letter landing on top of a space pays it on the way in — which is what
    /// keeps `sched` + space + `t` from becoming one word. Same rule as
    /// `SpaceBarGestureOrderTests`, reached through the new path.
    func testAnOpenSpaceBarIsPaidBeforeTheLetterThatInterruptedIt() {
        let (controller, target) = controller("sched")

        controller.spaceBarTouch(.began)
        controller.characterTouch(.began(.character("t"), CGPoint(x: 0.5, y: 0.5)))

        XCTAssertEqual(
            target.text, "sched ",
            "the space the other thumb was still holding was not typed before the letter")
        XCTAssertEqual(
            controller.spaceTouch.state, .spent,
            "the space bar still owes a space it has already been paid for")

        controller.characterTouch(.ended)
        XCTAssertEqual(target.text, "sched t")
    }

    /// **The one order the two open touches can be in, and the only way to reach
    /// it is three fingers.** A letter landing on an open space bar pays that
    /// space on the way in, so a letter that is still parked while a space is
    /// owed was parked *before* the space bar was touched — a thumb resting on
    /// `a`, the other thumb on space, and a third key pressed under both. Paying
    /// the space first there spells `a b` as ` ab`, and it is easy to reach by
    /// accident: `commitCharacterTouch` goes back through `press`, which pays open
    /// touches of its own, so the nested call will settle the space out of order
    /// unless the debt is claimed before the character is committed.
    func testASpaceOpenedAfterAHeldLetterStillLandsAfterThatLetter() {
        let (controller, target) = controller()

        controller.characterTouch(.began(.character("a"), CGPoint(x: 0.5, y: 0.5)))
        controller.spaceBarTouch(.began)
        controller.characterTouch(.began(.character("b"), CGPoint(x: 0.5, y: 0.5)))

        XCTAssertEqual(
            target.text, "a ",
            "the space bar was touched after the letter and its space landed in front of it")

        controller.characterTouch(.ended)
        XCTAssertEqual(target.text, "a b")
    }

    // MARK: The popup

    /// **An alternate replaces the letter rather than being appended to it, and
    /// the letter it replaces is still the one this key typed.**
    ///
    /// `KeyView.endPress` reports `.ended` before the popup's pick runs, so the
    /// base letter is in the field for the length of one function call and
    /// `KeyboardView.alternateHandler` is still the delete-then-retype it always
    /// was. The seeded `c` is what makes this test able to tell the two failures
    /// apart: a build that appended instead of replacing gives `caà`, and the
    /// tidier-looking build that drops the pending character and lets the handler
    /// delete anyway gives `à` — it eats the character in front of the word.
    func testAnAlternateReplacesTheLetterRatherThanAppendingToIt() throws {
        let (controller, target) = controller("c")
        let view = KeyboardView(controller: controller)
        let spec = try letterSpec("a")
        let handler = try XCTUnwrap(
            view.alternateHandler(for: spec), "English a carries accents and must have a handler")

        controller.characterTouch(.began(.character("a"), CGPoint(x: 0.5, y: 0.5)))
        controller.characterTouch(.ended)
        handler("à")

        XCTAssertEqual(target.text, "cà", "the accent did not replace the letter under it")
    }

    /// A word reached through the accents popup is a word placed by hand, so the
    /// space bar must not correct it — `צ׳יפס`, `col·legi` and `café` are exactly
    /// the words no dictionary holds. See `.claude/rules/suggestion-bar.md`.
    ///
    /// **The field is empty on purpose, and that is the half the popup never
    /// had.** The protection used to ride on the handler's `deleteBackward()`,
    /// which snapshots the word *left standing* — so an accent on the first
    /// letter of a word left `""`, and `isCorrectingWordByHand` refuses an empty
    /// prefix because it is a prefix of every word. `insertAlternate` retakes the
    /// snapshot from the word the pick actually left in the field.
    func testAnAccentStillCountsAsAHandRepair() throws {
        let (controller, _) = controller()
        let view = KeyboardView(controller: controller)
        let handler = try XCTUnwrap(view.alternateHandler(for: try letterSpec("a")))

        controller.characterTouch(.began(.character("a"), CGPoint(x: 0.5, y: 0.5)))
        controller.characterTouch(.ended)
        handler("à")

        XCTAssertTrue(
            controller.isCorrectingWordByHand,
            "a letter placed through the popup is no longer protected from autocorrect")
    }

    /// **The same protection carried through the letters typed after the mark,
    /// which is where autocorrect would actually strike.** `צ׳יפס` is the word
    /// the rule is written about and its geresh is on the *first* letter, so
    /// nothing stands behind the popup's delete and the old snapshot was empty
    /// for the whole word. Space is what would swap it, and space is four
    /// keystrokes later.
    ///
    /// The control half at the end is what rejects the over-broad repair: a fix
    /// that armed the flag on every insert, rather than on the popup's own, would
    /// protect a word nobody has touched and switch autocorrect off for good.
    func testTheProtectionSurvivesTypingOnFromAMarkOnTheFirstLetter() throws {
        let (controller, target) = controller()
        controller.language = .hebrew
        let view = KeyboardView(controller: controller)
        let handler = try XCTUnwrap(
            view.alternateHandler(for: try letterSpec("צ", in: .hebrew)),
            "every Hebrew letter carries its geresh")

        controller.characterTouch(.began(.character("צ"), CGPoint(x: 0.5, y: 0.5)))
        controller.characterTouch(.ended)
        handler("צ׳")
        XCTAssertEqual(target.text, "צ׳", "the geresh did not replace the letter it belongs to")

        for letter in "יפס" { controller.press(.character(String(letter))) }

        XCTAssertEqual(target.text, "צ׳יפס")
        XCTAssertTrue(
            controller.isCorrectingWordByHand,
            "typing on from a hand-placed mark lost the protection before the space that swaps it")

        // A second controller rather than a space, because a space commits the
        // word and `learnWordJustCommitted` would teach the shared store its own
        // vocabulary — the `PersonalLanguageModel` trap in
        // `.claude/rules/suggestion-bar.md`.
        let (typed, _) = self.controller()
        typed.language = .hebrew
        for letter in "צ׳יפס" { typed.press(.character(String(letter))) }
        XCTAssertFalse(
            typed.isCorrectingWordByHand,
            "the same word typed without the popup was protected, so nothing is corrected any more")
    }

    // MARK: Nothing may be stranded

    /// **The one path that discards instead of committing, and the only one.**
    ///
    /// `.claude/rules/keyboard-wiring.md`: iOS keeps one extension instance alive
    /// across fields *and across host apps*. A keyboard torn down mid-press is not
    /// promised a SwiftUI disappear callback, so the parked letter can outlive the
    /// field it was meant for — and `viewWillAppear` calling
    /// `prepareForNewDocument()` is the next thing that runs. Committing there
    /// would type a character from the last app into this one. The seeded text is
    /// what makes the failure visible: a build that commits gives `hia`.
    func testAHeldCharacterIsThrownAwayWhenTheKeyboardComesUpOverANewField() {
        let (controller, target) = controller("hi")

        controller.characterTouch(.began(.character("a"), CGPoint(x: 0.5, y: 0.5)))
        controller.prepareForNewDocument()

        XCTAssertNil(
            controller.pendingCharacter,
            "a character survived into a new field on a reused extension instance")
        XCTAssertEqual(
            target.text, "hi",
            "the character held over the last field was typed into this one")
    }

    /// And the discard cannot be undone by a stray lift arriving afterwards, which
    /// is exactly what a torn-down `KeyView` may still deliver.
    func testALiftArrivingAfterTheFieldChangedTypesNothing() {
        let (controller, target) = controller("hi")

        controller.characterTouch(.began(.character("a"), CGPoint(x: 0.5, y: 0.5)))
        controller.prepareForNewDocument()
        controller.characterTouch(.ended)

        XCTAssertEqual(target.text, "hi", "a late lift resurrected a discarded character")
    }

    // MARK: What the deferral must not change

    /// **A character nobody has typed yet must not make an empty field look
    /// full.** Fix and Rewrite are drawn disabled on an empty field, and the key
    /// and the bar both read this one published value so they cannot disagree
    /// (`.claude/rules/suggestion-bar.md`). Parking a letter changes the document
    /// not at all, so it must change this not at all either — and it must still
    /// flip the moment the letter actually lands.
    func testAHeldCharacterDoesNotMakeAnEmptyFieldLookLikeItHasText() {
        let (controller, _) = controller()
        controller.refreshDocumentState()
        XCTAssertFalse(controller.documentHasText, "the premise: the field starts empty")

        controller.characterTouch(.began(.character("a"), CGPoint(x: 0.5, y: 0.5)))

        XCTAssertFalse(
            controller.documentHasText,
            "a character that is only held made Fix and Rewrite look available")
        XCTAssertTrue(
            controller.isActionKeyDisabled(.quickTone),
            "Rewrite went live over a field that is still empty")

        controller.characterTouch(.ended)
        XCTAssertTrue(
            controller.documentHasText, "the released character did not wake the action keys")
    }

    /// **NIT-108 is about character keys, and the space bar's own behaviour is
    /// untouched.** A tap on space with no letter held still runs `insertSpace`
    /// on the lift exactly as it did, with `pendingAutocorrectUndo` intact.
    func testTheSpaceBarStillBehavesAsItDid() {
        let (controller, target) = controller("hi")

        controller.spaceBarTouch(.began)
        controller.spaceBarTouch(.ended(0))

        XCTAssertEqual(target.text, "hi ", "a plain space bar tap stopped typing a space")
        XCTAssertNil(controller.pendingCharacter, "the space bar parked a character of its own")
    }

    /// And delete's own two pieces of state are untouched: it still acts on the
    /// finger-down, and it still snapshots the word it left standing.
    func testDeleteStillSnapshotsTheWordItLeftStanding() {
        let (controller, target) = controller("hello")

        controller.press(.backspace)

        XCTAssertEqual(target.text, "hell", "delete stopped removing a character on its press")
        XCTAssertEqual(
            controller.deletedWordPrefix, "hell",
            "delete stopped recording the word being repaired by hand")
    }

    /// **`press` itself stays immediate, and three callers depend on it.** A
    /// VoiceOver rotor pick replays the press with no lift behind it
    /// (`KeyView.commitAlternate`), the accents handler retypes through it, and
    /// idle typing inserts through the same door. A `press` that parked would
    /// leave every one of them holding a character nothing would ever release.
    func testTheImmediatePressPathIsUntouched() {
        let (controller, target) = controller()

        controller.press(.character("a"))

        XCTAssertEqual(target.text, "a", "press no longer types on its own")
        XCTAssertNil(controller.pendingCharacter, "press parked its character instead of typing it")
    }

    /// One tap, one thud. The click and the thud stay on the finger-down, so the
    /// deferred press is told they are already spent; a build that forgot to say
    /// so buzzes twice for one key, which is the Emoji key's defect recorded in
    /// `.claude/rules/keyboard-layout.md`.
    func testADeferredKeystrokeBuzzesExactlyAsOftenAsAnImmediateOne() {
        SharedStore.shared.haptics = true
        let (controller, _) = controller()

        let beforeImmediate = Feedback.impactCount
        controller.press(.character("a"))
        let immediate = Feedback.impactCount - beforeImmediate

        let beforeDeferred = Feedback.impactCount
        controller.characterTouch(.began(.character("b"), CGPoint(x: 0.5, y: 0.5)))
        controller.characterTouch(.ended)
        let deferred = Feedback.impactCount - beforeDeferred

        XCTAssertEqual(immediate, 1, "an ordinary keystroke stopped answering the thumb")
        XCTAssertEqual(
            deferred, immediate,
            "a deferred keystroke buzzed \(deferred) times where an immediate one buzzes \(immediate)")
    }

    /// A search box is the one thing on this keyboard that types into something
    /// other than the document, and a deferred letter still has to reach it —
    /// through `press`, on the lift, exactly as an immediate one did.
    func testADeferredLetterStillTypesIntoTheEmojiSearchBox() {
        let (controller, target) = controller()
        controller.show(.emojiSearch)

        controller.characterTouch(.began(.character("c"), CGPoint(x: 0.5, y: 0.5)))
        XCTAssertEqual(controller.emojiQuery, "", "the query was written while the finger was down")

        controller.characterTouch(.ended)
        XCTAssertEqual(controller.emojiQuery, "c", "the released key did not reach the search box")
        XCTAssertEqual(target.text, "", "a key pointed at the search box wrote into the message")
    }

    /// A lift nobody pressed changes nothing. `KeyView.endPress` runs on paths a
    /// character key never opened — a plane switch under a delete, a cancelled
    /// gesture on the space bar — and the controller is what has to be indifferent
    /// to it.
    func testALiftWithNothingHeldTypesNothing() {
        let (controller, target) = controller("hi")

        controller.characterTouch(.ended)

        XCTAssertEqual(target.text, "hi", "a lift with no held character changed the document")
    }
}
