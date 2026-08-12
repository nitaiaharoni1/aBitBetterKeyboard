import XCTest

@testable import AIKeyboardCore

/// **Words appear in the field while somebody is speaking, and each reading
/// replaces the last one rather than being added to it.**
///
/// A transcript used to arrive once, at the end. The recorder publishes a better
/// reading of the same audio every couple of seconds now, so the keyboard's job is
/// no longer "insert a sentence" but "keep the tail of the field equal to the
/// utterance as currently understood" — and the difference between those two is
/// the difference between a message and the same message written out four times.
///
/// Every assertion here is on the *document*, not on `streamedDictation`. The
/// bookkeeping being right is not the claim; the field being right is.
@MainActor
final class DictationStreamingTests: XCTestCase {

    /// The whole feature in one case: three readings of one sentence leave one
    /// sentence. A build that appended instead would pass any assertion about the
    /// last words having arrived, which is why this asserts on the whole field.
    func testEachReadingReplacesTheOneBeforeIt() {
        let target = MockTextTarget(text: "")
        let controller = KeyboardController(target: target)
        controller.isDictating = true

        controller.streamDictation("hi")
        XCTAssertEqual(target.text, "hi")

        controller.streamDictation("hi mami")
        XCTAssertEqual(target.text, "hi mami")

        controller.streamDictation("hi mami what's up")
        XCTAssertEqual(target.text, "hi mami what's up")
    }

    /// **A reading is rewritten from the first character that differs, and the
    /// count it deletes is UTF-16 while the comparison is by `Character`.** Getting
    /// that pairing wrong lands the delete inside a grapheme cluster, which is the
    /// one way this can corrupt text rather than merely misplace it — so the case
    /// is written with a ZWJ family emoji (eight UTF-16 units, one character) that
    /// the second reading replaces, sitting inside Hebrew that it does not.
    func testAReadingRewrittenThroughAnEmojiKeepsTheTextIntact() {
        let target = MockTextTarget(text: "")
        let controller = KeyboardController(target: target)
        controller.isDictating = true

        controller.streamDictation("שלום 👨‍👩‍👧")
        controller.streamDictation("שלום 👨‍👩‍👧 מה נשמע")
        XCTAssertEqual(target.text, "שלום 👨‍👩‍👧 מה נשמע")

        controller.streamDictation("שלום 👋 מה נשמע?")
        XCTAssertEqual(target.text, "שלום 👋 מה נשמע?")
    }

    /// A recording that starts after something is typed puts a space in, and puts
    /// exactly one in however many readings arrive. The space is part of what was
    /// streamed, so a version that re-derived it on each replacement rather than
    /// remembering it would delete one character too few and leave `see you  hi`.
    func testTheSpaceInFrontIsWrittenOnceAndOnlyOnce() {
        let target = MockTextTarget(text: "see you")
        let controller = KeyboardController(target: target)
        controller.isDictating = true

        controller.streamDictation("thursday")
        XCTAssertEqual(target.text, "see you thursday")

        controller.streamDictation("thursday works")
        XCTAssertEqual(target.text, "see you thursday works")
    }

    /// **The final transcript replaces the drafts, it does not follow them.** It is
    /// a transcription of the whole utterance with all of the audio behind it, so
    /// it is the better text as well as the complete one — and appending it is the
    /// single most likely way to break this feature, because every partial before
    /// it looks like a prefix of it.
    func testTheFinalTranscriptReplacesEverythingStreamedBeforeIt() {
        let target = MockTextTarget(text: "")
        let controller = KeyboardController(target: target)
        controller.isDictating = true

        controller.streamDictation("hi mami what")
        controller.replaceStreamedDictation(with: "Hi Mami, what's up?")

        XCTAssertEqual(target.text, "Hi Mami, what's up?")
    }

    /// **A recording that streamed nothing inserts plainly**, which is what every
    /// recording did before this existed: an utterance shorter than the first
    /// partial, or one whose field moved, reaches the end with nothing of its own
    /// in the document.
    func testARecordingThatStreamedNothingStillInsertsItsTranscript() {
        let target = MockTextTarget(text: "ok")
        let controller = KeyboardController(target: target)
        controller.isDictating = true

        controller.replaceStreamedDictation(with: "sounds good")

        XCTAssertEqual(target.text, "ok sounds good")
    }

    /// **The field moving out from under a recording stops the streaming dead**,
    /// and this is the case that decides whether streaming is safe to ship at all.
    ///
    /// `replaceStreamedDictation` deletes a UTF-16 count backwards from the caret,
    /// so it must find exactly what it wrote still sitting at the end of the field.
    /// A user who types while speaking has moved it. Deleting the count anyway
    /// would eat their own characters — so nothing is deleted, nothing is repaired,
    /// and the recording stops streaming rather than appending a fresh copy of the
    /// sentence on every remaining partial.
    func testTypingDuringARecordingStopsItRewritingTheField() {
        let target = MockTextTarget(text: "")
        let controller = KeyboardController(target: target)
        controller.isDictating = true

        controller.streamDictation("hi mami")
        XCTAssertEqual(target.text, "hi mami")

        // The user types. The field no longer ends with what was streamed.
        controller.press(.character("!"))
        XCTAssertEqual(target.text, "hi mami!")

        controller.streamDictation("hi mami what's up")
        XCTAssertEqual(
            target.text, "hi mami!",
            "the recording deleted characters it did not write")

        // And it stays stopped, rather than appending a copy per partial.
        controller.streamDictation("hi mami what's up tonight")
        XCTAssertEqual(target.text, "hi mami!")
    }

    /// **A recording whose field moved still delivers its transcript**, and the
    /// first version of this did not: `replaceStreamedDictation` returned without
    /// inserting when it could not find its own draft, so a host that rewrote the
    /// field between the last partial and the final call silently threw the whole
    /// sentence away.
    ///
    /// The result is a duplicate — the abandoned draft plus the full transcript —
    /// and that is the deliberate half of the trade. A draft the user can delete
    /// is a worse field; a transcript the user never sees is a lost message, and
    /// there is nothing they can do about that one.
    func testTheTranscriptStillLandsWhenTheDraftCanNoLongerBeFound() {
        let target = MockTextTarget(text: "")
        let controller = KeyboardController(target: target)
        controller.isDictating = true
        controller.streamDictation("hi mami")

        // The host rewrites the field under the recording. Nothing tells the
        // keyboard this happened except the text no longer ending where it did.
        target.text = "hi mami and then some"

        controller.replaceStreamedDictation(with: "Hi Mami, what's up?")

        XCTAssertTrue(
            target.text.hasSuffix("Hi Mami, what's up?"),
            "the transcript was dropped because its draft could not be found")
        XCTAssertTrue(
            target.text.hasPrefix("hi mami and then some"),
            "the recording deleted text it did not write")
    }

    /// Nothing is streamed by a controller that is not recording. The partial
    /// publisher is a `@Published` on another object and fires on subscription, so
    /// without this guard subscribing after a recording ended would replay the last
    /// utterance into whatever field the keyboard is now over.
    func testNothingIsStreamedWhenNoRecordingIsOpen() {
        let target = MockTextTarget(text: "already here")
        let controller = KeyboardController(target: target)

        controller.streamDictation("hi mami")

        XCTAssertEqual(target.text, "already here")
    }

    /// **A dictation longer than the host's context window keeps streaming, and
    /// the first version of this stopped dead partway through one.**
    ///
    /// `documentContextBeforeInput` is a *window*: iOS truncates it and there is
    /// nothing behind it to reach for. A guard written against the whole draft can
    /// therefore never be satisfied once the draft outgrows that window — so
    /// streaming would abandon itself in the middle of exactly the long dictations
    /// it exists for, and hand the user a duplicated sentence at the end for its
    /// trouble. The guard is against the run about to be *deleted* instead, which
    /// is a word or two and always inside the window.
    ///
    /// 24 characters here against a draft several times that: nothing about the
    /// number matters except that the draft cannot fit in it.
    func testStreamingSurvivesAFieldTheKeyboardCanOnlyPartlyReadBack() {
        let target = WindowedTextTarget(window: 24)
        let controller = KeyboardController(target: target)
        controller.isDictating = true

        controller.streamDictation("the quick brown fox jumps")
        controller.streamDictation("the quick brown fox jumps over the lazy")
        controller.streamDictation("the quick brown fox jumps over the lazy dog today")
        XCTAssertEqual(target.text, "the quick brown fox jumps over the lazy dog today")

        // And a reading that rewrites the tail, still past the window.
        controller.streamDictation("the quick brown fox jumps over the lazy dogs tonight")
        XCTAssertEqual(target.text, "the quick brown fox jumps over the lazy dogs tonight")
    }

    /// The same window, and now the user types into it. The safety guarantee has
    /// to survive the relaxed guard: nothing this recording did not write may be
    /// deleted, whether or not the draft is longer than what can be read back.
    func testATruncatedWindowStillCatchesTheUserTyping() {
        let target = WindowedTextTarget(window: 24)
        let controller = KeyboardController(target: target)
        controller.isDictating = true

        controller.streamDictation("the quick brown fox jumps over the lazy")
        controller.press(.character("!"))
        XCTAssertEqual(target.text, "the quick brown fox jumps over the lazy!")

        controller.streamDictation("the quick brown fox jumps over the lazy dog")
        XCTAssertEqual(
            target.text, "the quick brown fox jumps over the lazy!",
            "the recording wrote over a character the user typed")
    }

    /// **Cancelling a recording keeps the words, and this is deliberate.** The same
    /// call is what the extension makes as the keyboard goes off screen
    /// (`viewWillDisappear`), so a version that deleted what had been streamed
    /// would take text out of somebody's message on the way out.
    func testCancellingARecordingLeavesWhatWasAlreadySaid() {
        let target = MockTextTarget(text: "")
        let controller = KeyboardController(target: target)
        controller.isDictating = true
        controller.streamDictation("hi mami")

        controller.stopDictation(insert: false)

        XCTAssertEqual(target.text, "hi mami")
        XCTAssertEqual(
            controller.streamedDictation, "",
            "the next recording would try to delete text this one no longer owns")
    }
}

// MARK: - A field the keyboard can only partly read back

/// A document that hands back a bounded window of what is in front of the caret,
/// the way a real `UITextDocumentProxy` does.
///
/// **`MockTextTarget` returns the whole string, which is the one thing a real host
/// never promises.** `documentContextBeforeInput` is documented as possibly
/// truncated and is, so a test that only ever sees the whole document cannot
/// notice a guard that stops working once the text outgrows the window — which is
/// precisely the failure streaming would have had on a long dictation.
private final class WindowedTextTarget: TextTarget {

    var text: String
    private let window: Int

    init(text: String = "", window: Int) {
        self.text = text
        self.window = window
    }

    var documentContextBeforeInput: String? { String(text.suffix(window)) }
    var documentContextAfterInput: String? { "" }
    var selectedText: String? { nil }
    var isSecureTextEntry: Bool? { false }
    var textContentType: UITextContentType?? { .some(.none) }

    func insertText(_ newText: String) { text.append(newText) }
    func deleteBackward() { if !text.isEmpty { text.removeLast() } }
    func adjustTextPosition(byCharacterOffset offset: Int) {}
}
