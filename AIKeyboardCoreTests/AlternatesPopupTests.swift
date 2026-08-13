import SwiftUI
import XCTest

@testable import AIKeyboardCore

/// The long-press popup: when it is on screen, and what a lift takes from it.
///
/// **The gesture cannot be driven from here**, the way `ToneAlternatesTests`
/// says of the same popup, so what these measure is the arithmetic underneath
/// it: `alternatesHoldDelay` decides how long the hold that opens it is
/// (200ms on a letter, 50ms on punctuation), `alternateIndex(at:)` maps a
/// point to an item, and `hasSlid` decides whether the point is worth reading
/// at all. A `KeyView` is a value, so it can be built and asked without ever
/// being rendered.
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

    private func recordingKey(
        _ spec: KeySpec, tones: [String] = [], fixes: [String] = []
    ) -> (KeyView, Recorder) {
        let recorder = Recorder()
        let view = KeyView(
            spec: spec,
            width: 34,
            height: 44,
            language: .hebrew,
            shift: .off,
            toneAlternates: tones,
            fixAlternates: fixes,
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

    // MARK: The press balloon

    /// **A letter draws a callout on tap even when it has a long-press popup.**
    /// Gating on `hasAlternates` left Hebrew with no tap feedback at all — every
    /// letter carries a geresh, so the thumb covered the glyph and nothing rose
    /// above it. English `a` and Russian `е` are the same shape. `q` has no
    /// popup and must still draw one, or a key with nothing else to show is
    /// mute.
    ///
    /// The two balloons still cannot be up at once: a hold that has opened the
    /// strip hides the callout. Asserting that half is what rejects the version
    /// that stacked ח on top of ח beside ח׳.
    func testALetterDrawsACalloutOnPressEvenWhenItHasAPopup() throws {
        for character in ["מ", "ח", "צ", "ק"] {
            let view = try letterKey(character, in: .hebrew)
            XCTAssertTrue(view.hasAlternates, "\(character) is the Hebrew case this exists for")
            XCTAssertTrue(view.showsCharacterCallout, "\(character) must preview on tap")
            XCTAssertTrue(
                view.drawsCharacterCallout(popupIsVisible: false),
                "\(character) is a letter under a thumb and must preview")
            XCTAssertFalse(
                view.drawsCharacterCallout(popupIsVisible: true),
                "\(character) would draw the callout and the strip together")
        }
        XCTAssertTrue(try letterKey("a", in: .english).drawsCharacterCallout(popupIsVisible: false))
        XCTAssertFalse(try letterKey("a", in: .english).drawsCharacterCallout(popupIsVisible: true))
        XCTAssertTrue(try letterKey("е", in: .russian).drawsCharacterCallout(popupIsVisible: false))

        let q = try letterKey("q", in: .english)
        XCTAssertFalse(q.hasAlternates)
        XCTAssertTrue(q.drawsCharacterCallout(popupIsVisible: false))
        XCTAssertTrue(q.showsCharacterCallout)
    }

    /// A digit is a character the thumb covers the same way a letter is.
    func testADigitDrawsACalloutOnPress() throws {
        let one = try XCTUnwrap(
            KeyboardLayout.rows(for: .english, plane: .numbers).flatMap(\.keys)
                .first { $0.cap == .character("1") },
            "the numbers plane has no 1 key")
        XCTAssertTrue(key(one, language: .english).drawsCharacterCallout(popupIsVisible: false))
    }

    /// The punctuation key still skips it: its cap already wears the marks, and
    /// previewing a lone period for the hold delay is the two-step open that was
    /// pulled. Function keys and grouped caps have nothing a single balloon can
    /// name.
    func testThePunctuationKeyAndNonLettersSkipTheCallout() throws {
        let punctuation = try XCTUnwrap(
            KeyboardLayout.bottomRow(for: .hebrew, plane: .letters, showsGlobe: true).keys
                .first { $0.addressableID == KeyboardLayout.punctuationKeyID })
        let view = key(punctuation, language: .hebrew)
        XCTAssertTrue(view.hasAlternates)
        XCTAssertFalse(view.drawsCharacterCallout(popupIsVisible: false))
        XCTAssertFalse(view.showsCharacterCallout)

        XCTAssertFalse(key(KeySpec(.space), language: .hebrew).drawsCharacterCallout(popupIsVisible: false))
        XCTAssertFalse(key(KeySpec(.shift), language: .hebrew).drawsCharacterCallout(popupIsVisible: false))

        let grouped = key(
            KeySpec(.character("קר\nאט"), groupedLetters: ["ק", "ר", "א", "ט"]),
            language: .hebrew)
        XCTAssertFalse(
            grouped.drawsCharacterCallout(popupIsVisible: false),
            "a grouped cap is several letters; a single balloon would name the wrong thing")
    }

    /// **A one-letter line must not jump to a larger font than its two-letter
    /// neighbour on an equal-width cap.** Sizing by `width / letterCount` made
    /// `ו` look like a different-sized button beside `קר` even after the width
    /// solver had already given them the same share.
    func testGroupedLettersOnEqualCapsShareAFontSize() {
        let width: CGFloat = 72
        let one = key(
            KeySpec(.character("ו\nע"), groupedLetters: ["ו", "ע"]),
            language: .hebrew, width: width)
        let two = key(
            KeySpec(.character("קר\nשד"), groupedLetters: ["ק", "ר", "ש", "ד"]),
            language: .hebrew, width: width)
        XCTAssertEqual(
            one.groupedFontSize("ו\nע"), two.groupedFontSize("קר\nשד"), accuracy: 0.5)
        XCTAssertEqual(KeyView.groupedLetterSpacing, 0)
    }

    /// The balloon has to be larger than the key it grew out of, or it is not a
    /// preview — it is the same glyph under the thumb.
    func testTheCalloutIsLargerAndHeavierThanTheKeyCap() throws {
        let view = try letterKey("מ", in: .hebrew)
        XCTAssertGreaterThan(view.calloutBubbleSize, view.width)
        XCTAssertGreaterThan(view.calloutFontSize, view.characterFontSize)
        XCTAssertGreaterThan(KeyView.calloutNeckHeight, 0)
    }

    /// Letters still wait 200ms, never zero: a popup that opened on
    /// finger-down would be on screen for the length of every keystroke.
    func testTheHoldIsShortAndIsNotInstant() {
        XCTAssertEqual(KeyView.alternatesDelay, .milliseconds(200))
        XCTAssertGreaterThan(KeyView.alternatesDelay, .zero)
        XCTAssertLessThan(
            KeyView.alternatesDelay, .milliseconds(250),
            "the callout fills the wait; a longer hold still reads as a keyboard that has not noticed")
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

    /// And the one keys that must *not* be pressed first, for the opposite
    /// reason: they deliberately run nothing on press, so their handler has
    /// nothing to undo and a replayed press would spend a model call on the
    /// default pass.
    func testAVoiceOverActionOnTheRewriteKeyDoesNotPressIt() {
        let (view, recorder) = recordingKey(
            KeySpec(.quickTone), tones: ["Clearer", "Friendly"])
        view.commitAlternate("Friendly")
        XCTAssertEqual(recorder.log, ["alternate"])
        XCTAssertTrue(recorder.presses.isEmpty)
        XCTAssertEqual(recorder.alternates, ["Friendly"])
    }

    func testAVoiceOverActionOnTheFixKeyDoesNotPressIt() {
        let (view, recorder) = recordingKey(
            KeySpec(.aiFix), fixes: ["Fix", "Spelling"])
        view.commitAlternate("Spelling")
        XCTAssertEqual(recorder.log, ["alternate"])
        XCTAssertTrue(recorder.presses.isEmpty)
        XCTAssertEqual(recorder.alternates, ["Spelling"])
    }

    /// Every popup item is reachable without the gesture, which is the rule the
    /// registers were given a rotor route under. It matters more now than it did
    /// then: the geresh, the gershayim and the interpunt are on no plane, so the
    /// popup is the only place they exist.
    func testEveryAlternateHasAName() throws {
        let hebrew = try letterKey("ח", in: .hebrew)
        XCTAssertEqual(
            hebrew.alternatePickerItems.map(hebrew.alternateActionLabel),
            ["Insert ח׳", "Insert ח״"])

        let catalan = try letterKey("l", in: .catalan)
        XCTAssertTrue(catalan.alternateItems.contains("l·"))
        XCTAssertEqual(catalan.alternateActionLabel("l·"), "Insert l·")

        let tone = recordingKey(KeySpec(.quickTone), tones: ["Clearer", "Friendly"]).0
        XCTAssertEqual(tone.alternateActionLabel("Friendly"), "Rewrite as Friendly")

        let fix = recordingKey(KeySpec(.aiFix), fixes: ["Fix", "Spelling"]).0
        XCTAssertEqual(fix.alternateActionLabel("Spelling"), "Fix as Spelling")
        XCTAssertEqual(fix.alternatePickerItems, ["Spelling"])
        XCTAssertTrue(fix.runsOnLift)
        XCTAssertEqual(fix.alternateRestIndex, 0)
    }

    /// Same standing-finger rule as a letter, on a stack: the point under a
    /// finger that never moved is not item 0, so rest has to keep Fix.
    func testAStandingFingerOnFixKeepsProofread() {
        let view = recordingKey(
            KeySpec(.aiFix), fixes: ["Fix", "Spelling", "Punctuate", "Polish"]).0
        XCTAssertTrue(view.runsOnLift)
        XCTAssertEqual(view.alternateItems, ["Fix", "Spelling", "Punctuate", "Polish"])
        let centre = CGPoint(x: 17, y: 22)
        XCTAssertNotEqual(view.alternateIndex(at: centre), 0)
        XCTAssertEqual(
            view.alternateIndexOnLift(
                popupIsVisible: true, translation: .zero, location: centre),
            0)
        XCTAssertEqual(
            view.alternateIndexOnLift(
                popupIsVisible: true,
                translation: CGSize(width: 0, height: -20),
                location: CGPoint(x: 17, y: -20)),
            view.alternateIndex(at: CGPoint(x: 17, y: -20)))
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

    // MARK: The period key

    private func punctuationKeyView(language: KeyboardLanguage = .hebrew) throws -> KeyView {
        let spec = try XCTUnwrap(
            KeyboardLayout.bottomRow(for: language, plane: .letters, showsGlobe: true).keys
                .first { $0.addressableID == KeyboardLayout.punctuationKeyID })
        return key(spec, language: language)
    }

    /// Punctuation opens after 50ms; a letter still waits 200ms. Asserting both
    /// and that they differ is what rejects collapsing them back to one number.
    func testThePunctuationHoldIsShorterThanALetterHold() throws {
        XCTAssertEqual(KeyView.punctuationAlternatesDelay, .milliseconds(50))
        let punctuation = try punctuationKeyView()
        let letter = try letterKey("ח", in: .hebrew)
        XCTAssertEqual(punctuation.alternatesHoldDelay, .milliseconds(50))
        XCTAssertEqual(letter.alternatesHoldDelay, .milliseconds(200))
        XCTAssertEqual(punctuation.alternatesHoldDelay, KeyView.punctuationAlternatesDelay)
        XCTAssertEqual(letter.alternatesHoldDelay, KeyView.alternatesDelay)
        XCTAssertNotEqual(
            punctuation.alternatesHoldDelay, letter.alternatesHoldDelay,
            "punctuation 50ms and letters 200ms must stay two waits")
    }

    /// SwiftKey's order, not `. , ? ! '`. The numbers row still prints those
    /// five; this popup is the six a thumb reaches without leaving the letters
    /// plane. Arabic and Greek swap in the comma and question mark they write.
    func testThePeriodPopupIsOrderedLikeSwiftKey() throws {
        XCTAssertEqual(
            try punctuationKeyView().alternateItems, ["!", "@", "#", ",", ".", "?"])
        XCTAssertEqual(try punctuationKeyView().alternateRestIndex, 4)
        XCTAssertEqual(
            try punctuationKeyView().alternatePickerItems, ["!", "@", "#", ",", "?"])
        XCTAssertEqual(
            try punctuationKeyView(language: .arabic).alternateItems,
            ["!", "@", "#", "،", ".", "؟"])
        XCTAssertEqual(
            try punctuationKeyView(language: .greek).alternateItems,
            ["!", "@", "#", ",", ".", ";"])
    }

    /// The strip is aligned so the period sits over the key, then clamped so the
    /// question mark is not cut off by the right edge. A centred six-item strip
    /// on this key overruns a phone-width canvas; asserting both the overrun and
    /// the clamp is what rejects a build that only recentres.
    func testThePeriodPopupStaysInsideTheKeyboard() throws {
        let view = try punctuationKeyView()
        let keyMinX: CGFloat = 360
        let canvas: CGFloat = 393
        let centredTrailing = keyMinX + view.width / 2 + view.alternatesWidth / 2
        XCTAssertGreaterThan(
            centredTrailing, canvas,
            "the unclamped strip must overrun, or this is not testing the period key")

        let dx = view.alternatesStripOffset(keyMinX: keyMinX, canvasWidth: canvas)
        let leading = keyMinX + (view.width - view.alternatesWidth) / 2 + dx
        let trailing = leading + view.alternatesWidth
        XCTAssertGreaterThanOrEqual(leading, Theme.Radius.chip)
        XCTAssertLessThanOrEqual(trailing, canvas - Theme.Radius.chip)

        let centre = CGPoint(x: view.width / 2, y: view.height / 2)
        XCTAssertEqual(
            view.alternateIndexOnLift(
                popupIsVisible: true, translation: .zero, location: centre),
            view.alternateRestIndex,
            "a finger that never moved must keep the period, even after the strip shifts")
    }

    /// The period key's real x on a phone-width Hebrew keyboard, not a round
    /// number. `testThePeriodPopupStaysInsideTheKeyboard` feeds 360; this one
    /// solves the bottom row so a width or inset change cannot quietly miss
    /// the clamp.
    func testThePeriodPopupStaysInsideAPhoneWidthHebrewKeyboard() throws {
        for canvas: CGFloat in [375, 393, 402] {
            let row = KeyboardLayout.bottomRow(for: .hebrew, plane: .letters, showsGlobe: true)
            let available = canvas - Theme.Metrics.sideInset * 2
            let widths = KeyboardLayout.widths(
                for: row,
                totalWidth: available,
                unitWidth: 1,
                spacing: Theme.Metrics.keySpacing)
            let index = try XCTUnwrap(
                row.keys.firstIndex { $0.addressableID == KeyboardLayout.punctuationKeyID })
            var keyMinX = Theme.Metrics.sideInset
            for i in 0..<index {
                keyMinX += widths[i] + Theme.Metrics.keySpacing
            }
            let view = key(row.keys[index], language: .hebrew, width: widths[index])
            let dx = view.alternatesStripOffset(keyMinX: keyMinX, canvasWidth: canvas)
            let leading = keyMinX + (view.width - view.alternatesWidth) / 2 + dx
            let trailing = leading + view.alternatesWidth
            XCTAssertGreaterThanOrEqual(
                leading, Theme.Radius.chip, "canvas \(canvas) leading \(leading)")
            XCTAssertLessThanOrEqual(
                trailing, canvas - Theme.Radius.chip,
                "canvas \(canvas) trailing \(trailing) overruns \(canvas)")
        }
    }

    /// Feeding `keyMinX == 0` with a real canvas is the named-space miss: the
    /// clamp treats a right-edge key as a left-edge one and shifts the strip
    /// further off screen. Asserting the overrun is what rejects putting that
    /// 0 back into production.
    func testAZeroCanvasXShiftsThePeriodPopupOffTheRightEdge() throws {
        let view = try punctuationKeyView()
        let actualKeyMinX: CGFloat = 360
        let canvas: CGFloat = 393
        let dx = view.alternatesStripOffset(keyMinX: 0, canvasWidth: canvas)
        let leading = actualKeyMinX + (view.width - view.alternatesWidth) / 2 + dx
        let trailing = leading + view.alternatesWidth
        XCTAssertGreaterThan(
            trailing, canvas,
            "a zero canvas x must overrun, or this is not testing the miss")
    }

    /// Slide right of the period reaches `?`, the way SwiftKey's flick does.
    func testASlideRightOfThePeriodReachesTheQuestionMark() throws {
        let view = try punctuationKeyView()
        let period = CGPoint(x: 17, y: 22)
        XCTAssertEqual(view.alternateIndex(at: period), 4)
        XCTAssertEqual(view.alternateItems[4], ".")
        XCTAssertEqual(view.alternateIndex(at: CGPoint(x: 51, y: 22)), 5)
        XCTAssertEqual(view.alternateItems[5], "?")
        XCTAssertEqual(
            view.alternateIndexOnLift(
                popupIsVisible: true,
                translation: CGSize(width: 34, height: 0),
                location: CGPoint(x: 51, y: 22)),
            5)
    }
}
