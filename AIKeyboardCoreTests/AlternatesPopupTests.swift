import SwiftUI
import XCTest

@testable import AIKeyboardCore

/// The long-press popup: when it is on screen, and what a lift takes from it.
///
/// **The gesture cannot be driven from here**, the way `ToneAlternatesTests`
/// says of the same popup, so what these measure is the arithmetic underneath
/// it: `alternatesDelay` decides how long the hold that opens it is,
/// `alternateIndex(at:)` maps a point to an item, and `hasSlid` decides whether
/// the point is worth reading at all. A `KeyView` is a value, so it can be
/// built and asked without ever being rendered.
final class AlternatesPopupTests: XCTestCase {

    /// A key the way `KeyboardView` builds one, at the width a ten-column
    /// letter row works out to on an iPhone 17 Pro.
    private func key(
        _ spec: KeySpec, language: KeyboardLanguage, width: CGFloat = 34
    ) -> KeyView {
        KeyView(
            spec: spec,
            width: width,
            height: 44,
            language: language,
            shift: .off,
            onPress: { _, _ in },
            // `KeyboardView.alternateHandler(for:)` hands one to every key that
            // has alternates and nil to the rest, and the popup is gated on it.
            onAlternate: spec.alternates.isEmpty ? nil : { _ in })
    }

    /// What a key did, in the order it did it. `KeyboardView` wires both of these
    /// to the controller, so the order is the whole of what a VoiceOver action
    /// puts in the user's document.
    private final class Recorder {
        var presses: [KeyCap] = []
        var alternates: [String] = []
        var log: [String] = []
    }

    private func recordingKey(_ spec: KeySpec, tones: [String] = []) -> (KeyView, Recorder) {
        let recorder = Recorder()
        let view = KeyView(
            spec: spec,
            width: 34,
            height: 44,
            language: .hebrew,
            shift: .off,
            toneAlternates: tones,
            onPress: { cap, _ in
                recorder.presses.append(cap)
                recorder.log.append("press")
            },
            onAlternate: { item in
                recorder.alternates.append(item)
                recorder.log.append("alternate")
            })
        return (view, recorder)
    }

    private func letterKey(_ character: String, in language: KeyboardLanguage) throws -> KeyView {
        let spec = try XCTUnwrap(
            KeyboardLayout.rows(for: language, plane: .letters)
                .flatMap(\.keys)
                .first { $0.cap == .character(character) },
            "\(language.displayName) has no \(character) key")
        return key(spec, language: language)
    }

    // MARK: One balloon, not two

    /// **A key with a popup draws no press callout, so a hold shows one thing
    /// once.** They are two balloons in the same place drawing the same glyph:
    /// the callout on finger-down, then the popup replacing it, which played as
    /// ח, a beat, then ח beside ח׳. In Hebrew that was every letter of the
    /// alphabet, because every one of them carries a geresh.
    ///
    /// Asserting both halves, because dropping the callout from a key that has
    /// nothing else to show would leave that key with no press feedback at all.
    func testOnlyAKeyWithNothingElseToShowDrawsThePressCallout() throws {
        for character in ["ח", "צ", "ק"] {
            XCTAssertFalse(
                try letterKey(character, in: .hebrew).showsCharacterCallout,
                "\(character) draws a callout and then a popup over it")
        }
        XCTAssertFalse(try letterKey("a", in: .english).showsCharacterCallout)
        XCTAssertFalse(try letterKey("е", in: .russian).showsCharacterCallout, "е offers ё")

        // `q` has no alternates, so the callout is the only thing it can show.
        XCTAssertTrue(try letterKey("q", in: .english).showsCharacterCallout)
        XCTAssertFalse(try letterKey("q", in: .english).hasAlternates)
    }

    /// The punctuation key is no longer the one key that skips the callout: it
    /// skips it for the same reason every other popup key now does.
    func testThePunctuationKeyIsNoLongerASpecialCase() throws {
        let punctuation = try XCTUnwrap(
            KeyboardLayout.bottomRow(for: .hebrew, plane: .letters, showsGlobe: true).keys
                .first { $0.addressableID == KeyboardLayout.punctuationKeyID })
        let view = key(punctuation, language: .hebrew)
        XCTAssertTrue(view.hasAlternates)
        XCTAssertFalse(view.showsCharacterCallout)
    }

    /// And the hold is one number, never zero: a popup that opened on
    /// finger-down would be on screen for the length of every keystroke.
    func testTheHoldIsShortAndIsNotInstant() {
        XCTAssertEqual(KeyView.alternatesDelay, .milliseconds(200))
        XCTAssertGreaterThan(KeyView.alternatesDelay, .zero)
        XCTAssertLessThan(
            KeyView.alternatesDelay, .milliseconds(250),
            "with no callout to fill it, a longer wait reads as a keyboard that has not noticed")
    }

    /// A key with nothing to offer never starts the wait at all.
    func testAKeyWithNoAlternatesHasNoPopup() throws {
        XCTAssertFalse(key(KeySpec(.space), language: .hebrew).hasAlternates)
        XCTAssertFalse(try letterKey("q", in: .english).hasAlternates)
    }

    // MARK: The one item that draws nothing

    /// **Persian's half-space is drawn as `␣` and inserted as U+200C, and a test
    /// that only read the popup would pass on a build that inserted the wrong
    /// one.** U+200C has no width and does not join, so `ی` and `ی‌` are the same
    /// picture: without the substitution the popup offers what looks like the
    /// same letter twice, and the second chip reads as a bug. Both halves are
    /// asserted because the whole point is that they differ.
    func testThePersianHalfSpaceIsDrawnButNotTyped() throws {
        let key = try letterKey("ی", in: .persian)
        let halfSpace = try XCTUnwrap(key.alternateItems.last)

        XCTAssertEqual(halfSpace, "ی\u{200C}", "what is inserted is the real character")
        XCTAssertEqual(key.displayLabel(halfSpace), "ی␣", "what is drawn has something to see")
        XCTAssertNotEqual(
            key.displayLabel(halfSpace), key.displayLabel(key.alternateItems[0]),
            "the popup draws the same glyph twice")
        XCTAssertEqual(key.alternateActionLabel(halfSpace), "Insert ی␣")
    }

    /// And nothing else is rewritten on the way to the popup, in any of the
    /// sixty-four layouts. The substitution is one character, not a scheme.
    func testNoOtherAlternateIsDrawnAsSomethingElse() {
        for language in KeyboardLanguage.allCases where language != .persian {
            for plane in [KeyboardPlane.letters, .numbers, .symbols] {
                for spec in KeyboardLayout.rows(for: language, plane: plane).flatMap(\.keys) {
                    let view = key(spec, language: language)
                    for item in view.alternateItems {
                        XCTAssertEqual(
                            view.displayLabel(item), item,
                            "\(language.displayName) draws \(item) as something else")
                    }
                }
            }
        }
    }

    // MARK: The route that is not a gesture

    /// **A VoiceOver action has to replay the press, and this is the assertion
    /// that rejects the version that does not.** `KeyboardView.alternateHandler`
    /// is written for the gesture, where the key already inserted its character
    /// on finger-down, so picking an alternate is delete-then-retype. An action
    /// invoked from the rotor has no finger-down behind it, so calling the
    /// handler alone deletes whatever the user wrote last and puts ח׳ in its
    /// place. Asserting the *order* is the point: a test that only checked that
    /// `onAlternate` ran passes on the version that eats a character.
    func testAVoiceOverActionOnALetterPressesFirstSoTheDeleteHasSomethingToUndo() throws {
        let spec = try XCTUnwrap(
            KeyboardLayout.rows(for: .hebrew, plane: .letters).flatMap(\.keys)
                .first { $0.cap == .character("ח") })
        let (view, recorder) = recordingKey(spec)
        view.commitAlternate("ח׳")
        XCTAssertEqual(recorder.log, ["press", "alternate"])
        XCTAssertEqual(recorder.presses, [.character("ח")])
        XCTAssertEqual(recorder.alternates, ["ח׳"])
    }

    /// And the one key that must *not* be pressed first, for the opposite
    /// reason: it deliberately runs nothing on press, so its handler has nothing
    /// to undo and a replayed press would spend a model call on the default tone.
    func testAVoiceOverActionOnTheRewriteKeyDoesNotPressIt() {
        let (view, recorder) = recordingKey(
            KeySpec(.quickTone), tones: ["Clearer", "Friendly"])
        view.commitAlternate("Friendly")
        XCTAssertEqual(recorder.log, ["alternate"])
        XCTAssertTrue(recorder.presses.isEmpty)
        XCTAssertEqual(recorder.alternates, ["Friendly"])
    }

    /// Every popup item is reachable without the gesture, which is the rule the
    /// registers were given a rotor route under. It matters more now than it did
    /// then: the geresh, the gershayim and the interpunt are on no plane, so the
    /// popup is the only place they exist.
    func testEveryAlternateHasAName() throws {
        let hebrew = try letterKey("ח", in: .hebrew)
        XCTAssertEqual(
            hebrew.alternateItems.dropFirst().map(hebrew.alternateActionLabel),
            ["Insert ח׳", "Insert ח״"])

        let catalan = try letterKey("l", in: .catalan)
        XCTAssertTrue(catalan.alternateItems.contains("l·"))
        XCTAssertEqual(catalan.alternateActionLabel("l·"), "Insert l·")

        let tone = recordingKey(KeySpec(.quickTone), tones: ["Clearer", "Friendly"]).0
        XCTAssertEqual(tone.alternateActionLabel("Friendly"), "Rewrite as Friendly")
    }

    // MARK: Handler path — shipping delete-then-retype route

    /// **Exercise the shipping `alternateHandler(for:)` path, not just the
    /// display-label model.** The handler lives on `KeyboardView` and does
    /// delete-then-retype: it calls `controller.deleteBackward()` to remove the
    /// base letter the finger-down already inserted, then
    /// `controller.press(.character(alternate))` to insert the pair. A test that
    /// only reads `displayLabel` or `alternateItems` passes on a build where the
    /// handler inserts the wrong bytes — this one doesn't.
    @MainActor
    func testThePersianHalfSpaceHandlerInsertsTheLetterPlusU200C() throws {
        // Set up a real controller with a MockTextTarget so we can read what
        // reaches the document.
        let target = MockTextTarget()
        let controller = KeyboardController(target: target, language: .persian)
        let view = KeyboardView(controller: controller)

        let ySpec = try XCTUnwrap(
            KeyboardLayout.rows(for: .persian, plane: .letters)
                .flatMap(\.keys)
                .first { $0.cap == .character("ی") },
            "Persian has no ی key")

        let handler = try XCTUnwrap(
            view.alternateHandler(for: ySpec),
            "ی must have an alternate handler (it carries U+200C)")

        // Simulate finger-down: the key inserts its base character on press.
        target.text = "ی"

        // The handler deletes the base letter and inserts the letter + half-space.
        handler("ی\u{200C}")

        XCTAssertEqual(
            target.text, "ی\u{200C}",
            """
            The alternate handler must delete the base ی and insert ی + U+200C. \
            Got "\(target.text.unicodeScalars.map { "U+\(String($0.value, radix: 16, uppercase: true))" }.joined(separator: " "))".
            """)
    }

    // MARK: What a lift takes from it

    /// **The measurement `hasSlid` exists for.** The popup is centred on the key
    /// rather than on its own first item, so the point under a finger that never
    /// moved is half the overhang into the strip: the boundary of items 0 and 1
    /// on a two-item popup, and the middle of item 4 on English's nine-item one.
    /// Reading that point on lift is what swapped ח for ח׳ — and `a` for the
    /// fifth accent — under a finger that had done nothing but rest.
    ///
    /// Asserting `!= 0` rather than a number is the point: any centred popup
    /// fails it, so a future change to the width or the item count cannot make
    /// this quietly true again.
    func testTheKeysOwnCentreIsNotTheFirstItemOfItsPopup() throws {
        let centre = CGPoint(x: 17, y: 22)
        XCTAssertNotEqual(try letterKey("ח", in: .hebrew).alternateIndex(at: centre), 0)
        XCTAssertNotEqual(try letterKey("a", in: .english).alternateIndex(at: centre), 0)
    }

    /// So a finger that has not travelled is not choosing.
    ///
    /// The wobble of a thumb resting on glass is a point or two; an item is 34
    /// wide. Both numbers are what six sits between.
    func testAFingerThatHasNotTravelledIsNotChoosing() throws {
        let key = try letterKey("ח", in: .hebrew)
        XCTAssertFalse(key.hasSlid(.zero), "a finger that never moved is resting")
        XCTAssertFalse(key.hasSlid(CGSize(width: 2, height: -3)), "that is a wobble")
        XCTAssertTrue(key.hasSlid(CGSize(width: 20, height: 0)), "that is a slide to the geresh")
        XCTAssertTrue(key.hasSlid(CGSize(width: 0, height: -20)), "the registers stack upward")
        XCTAssertLessThan(
            KeyView.slideThreshold, 34,
            "the threshold has grown past an item; the second one is now unreachable")
    }

    /// Drive the exact pure decision used by `DragGesture.onEnded`. The key's
    /// centre maps to item 1, so a version that reads location without consulting
    /// translation fails the first assertion. A real slide to the same point must
    /// still commit that item, so hardcoding zero fails the second.
    func testLiftKeepsTheBaseLetterUnlessTheFingerActuallySlid() throws {
        let key = try letterKey("ח", in: .hebrew)
        let centre = CGPoint(x: 17, y: 22)
        XCTAssertEqual(
            key.alternateIndexOnLift(
                popupIsVisible: true,
                translation: .zero,
                location: centre),
            0)
        XCTAssertEqual(
            key.alternateIndexOnLift(
                popupIsVisible: true,
                translation: CGSize(width: 20, height: 0),
                location: centre),
            1)
        XCTAssertEqual(
            key.alternateIndexOnLift(
                popupIsVisible: false,
                translation: CGSize(width: 20, height: 0),
                location: centre),
            0)
    }

    /// And the items a slide lands on are the two marks, which is the whole
    /// feature: the popup for ח is ח, ח׳, ח״.
    func testASlideAcrossTheStripReachesBothHebrewMarks() throws {
        let key = try letterKey("ח", in: .hebrew)
        XCTAssertEqual(key.alternateItems, ["ח", "ח׳", "ח״"])
        // Three items 34 wide centred on a 34-wide key span -34...68 in the key's
        // own space, so each item's middle is a key-width apart from the last.
        XCTAssertEqual(key.alternateIndex(at: CGPoint(x: -17, y: 22)), 0)
        XCTAssertEqual(key.alternateIndex(at: CGPoint(x: 17, y: 22)), 1)
        XCTAssertEqual(key.alternateIndex(at: CGPoint(x: 51, y: 22)), 2)
        // And past either end it clamps rather than running off the strip.
        XCTAssertEqual(key.alternateIndex(at: CGPoint(x: 400, y: 22)), 2)
        XCTAssertEqual(key.alternateIndex(at: CGPoint(x: -400, y: 22)), 0)
    }
}
