import UIKit
import XCTest

@testable import AIKeyboardCore

/// What the keys do while the emoji search box is open.
///
/// **This is the only state in the keyboard where a keystroke goes somewhere
/// other than the user's message**, so the assertions that matter are the ones
/// about the document *not* changing. A build that routed nothing would still
/// pass "the query is empty" — the query starts empty — which is why every test
/// here reads the document as well.
@MainActor
final class EmojiSearchTypingTests: XCTestCase {

    private func controller(_ text: String = "hello") -> (KeyboardController, MockTextTarget) {
        let target = MockTextTarget(text: text)
        return (KeyboardController(target: target), target)
    }

    /// Letters build the query and leave the message alone. The broken version
    /// typed "cat" into whatever the user was writing.
    func testTypingGoesToTheQueryAndNotToTheDocument() {
        let (controller, target) = controller()
        controller.show(.emojiSearch)

        for letter in ["c", "a", "t"] { controller.press(.character(letter)) }

        XCTAssertEqual(controller.emojiQuery, "cat")
        XCTAssertEqual(target.text, "hello", "the query was typed into the message")
        XCTAssertFalse(controller.emojiResults.isEmpty)
        XCTAssertEqual(controller.emojiResults.first, "🐈")
    }

    /// Hebrew, because the box exists so that `לב` finds ❤️.
    func testHebrewTypingSearchesRatherThanTyping() {
        let (controller, target) = controller("שלום")
        controller.show(.emojiSearch)

        for letter in ["פ", "י", "צ", "ה"] { controller.press(.character(letter)) }

        XCTAssertEqual(controller.emojiQuery, "פיצה")
        XCTAssertEqual(target.text, "שלום")
        XCTAssertEqual(controller.emojiResults.first, "🍕")
    }

    /// **Delete must never reach the message while it is pointed at the box.**
    /// Backspacing on an empty query closes search instead — the one thing a
    /// delete key must not do here is eat a character the user cannot see it
    /// eating.
    func testBackspaceEditsTheQueryThenClosesSearchRatherThanDeletingText() {
        let (controller, target) = controller("hello")
        controller.show(.emojiSearch)
        controller.press(.character("c"))
        controller.press(.character("a"))

        controller.press(.backspace)
        XCTAssertEqual(controller.emojiQuery, "c")
        XCTAssertEqual(target.text, "hello")

        controller.press(.backspace)
        XCTAssertEqual(controller.emojiQuery, "")
        XCTAssertEqual(target.text, "hello")

        // Empty now: the next one leaves search, still without touching the text.
        SharedStore.shared.haptics = true
        let impacts = Feedback.impactCount
        controller.press(.backspace)
        XCTAssertEqual(controller.overlay, .emoji)
        XCTAssertEqual(target.text, "hello", "backspace fell through to the document")
        XCTAssertEqual(
            Feedback.impactCount, impacts + 1,
            "empty-query backspace buzzed twice: keyPress then show")
    }

    func testForwardDeleteDoesNotTouchTheDocumentOrCloseSearch() {
        let (controller, target) = controller("hello")
        controller.show(.emojiSearch)
        controller.press(.deleteForward)
        XCTAssertEqual(controller.overlay, .emojiSearch)
        XCTAssertEqual(controller.emojiQuery, "")
        XCTAssertEqual(target.text, "hello")
    }

    /// Shift, the plane switch and the globe are deliberately *not* taken. The
    /// whole reason search hands the letters back is that the words being searched
    /// for are Hebrew or English, and a user who cannot reach the other alphabet
    /// can only search in one of them.
    func testTheKeysThatChangeWhichLettersAreOnScreenStillWork() {
        let (controller, _) = controller()
        controller.show(.emojiSearch)

        controller.press(.shift)
        XCTAssertEqual(controller.shift, .on)

        controller.press(.plane(.numbers, label: "123"))
        XCTAssertEqual(controller.plane, .numbers)
        XCTAssertEqual(controller.overlay, .emojiSearch, "changing plane closed the search")
    }

    /// A capital letter searches the same as a lowercase one — the catalogue is
    /// lowercased, and `normalise` is what makes "Cat" and "cat" one query.
    func testShiftDoesNotBreakTheSearch() {
        let (controller, _) = controller()
        controller.show(.emojiSearch)
        controller.press(.shift)
        controller.press(.character("c"))
        controller.press(.character("a"))
        controller.press(.character("t"))

        XCTAssertEqual(controller.emojiQuery, "Cat")
        XCTAssertEqual(controller.emojiResults.first, "🐈")
    }

    /// **The box must not inherit the document's shift, and it must give it back.**
    ///
    /// An empty field arms shift at focus, so `cat` was typed into the query as
    /// `Cat` and a shift press from that inherited `.on` reached `.locked`. The
    /// restore is the half that makes the fix safe rather than a swap of one bug
    /// for a worse one: leaving shift off after the box closes loses the capital at
    /// the start of the next sentence. Asserted through `dismissOverlay()` as well
    /// as `show(_:)`, because four call sites write `overlay` directly and the
    /// whole reason the fix lives in a `didSet` is that they cannot all be
    /// remembered.
    func testTheDocumentsShiftIsParkedForSearchAndGivenBack() {
        let (controller, _) = controller("")
        XCTAssertEqual(
            controller.shift, .on,
            "an empty field arms shift — that is the premise, and without it this passes for free")

        controller.show(.emojiSearch)
        XCTAssertEqual(controller.shift, .off, "the query inherited the document's capital")
        controller.press(.character("c"))
        XCTAssertEqual(controller.emojiQuery, "c")

        controller.show(.emoji)
        XCTAssertEqual(controller.shift, .on, "shift was left off once the box closed")

        controller.show(.emojiSearch)
        XCTAssertEqual(controller.shift, .off)
        controller.dismissOverlay()
        XCTAssertEqual(controller.shift, .on, "the dismiss path never restored it")
    }

    /// Shift pressed *inside* the box belongs to the query and is discarded with
    /// it. A restore that put the query's shift back into the document would
    /// capitalise the next word the user typed into their message.
    func testAShiftPressedInsideTheQueryDoesNotLeakIntoTheDocument() {
        let (controller, _) = controller("hello")
        controller.shift = .off

        controller.show(.emojiSearch)
        controller.press(.shift)
        XCTAssertEqual(controller.shift, .on, "shift is still live inside the box")

        controller.dismissOverlay()
        XCTAssertEqual(controller.shift, .off, "the query's own shift leaked into the document")
    }

    /// **The keyboard coming back on screen is the second door into the same
    /// bug.** Nothing resets `overlay` on the way out, so an extension instance
    /// iOS keeps alive returns with the box still open — and `viewWillAppear`
    /// calls `prepareForNewDocument()`, which reads the field's
    /// `autocapitalizationType` and used to write `shift` whatever was standing
    /// on the keys. The field here asks for `.allCharacters`, so a build that
    /// writes through locks the query into capitals; one that parks the answer
    /// keeps the box on lower case and still hands the *new* field's decision to
    /// the document. Both halves are asserted, because parking the old value
    /// unchanged passes the first and fails the second.
    func testAKeyboardReturningOverAnOpenBoxReadsTheFieldWithoutArmingTheQuery() {
        let target = MockTextTarget(text: "")
        target.autocapitalizationType = UITextAutocapitalizationType.allCharacters
        let controller = KeyboardController(target: target)

        controller.show(.emojiSearch)
        XCTAssertEqual(controller.shift, .off)

        controller.prepareForNewDocument()

        XCTAssertEqual(controller.shift, .off, "the field's trait armed the query")
        controller.press(.character("c"))
        XCTAssertEqual(controller.emojiQuery, "c", "the query was capitalised by a field trait")

        controller.dismissOverlay()
        XCTAssertEqual(
            controller.shift, .locked,
            "the field this keyboard came back over never reached the document")
    }

    /// Picking a result inserts it and leaves the query up, so two emoji can be
    /// picked from one search.
    func testPickingAResultInsertsItAndKeepsTheSearchOpen() {
        let (controller, target) = controller("")
        controller.show(.emojiSearch)
        for letter in ["c", "a", "t"] { controller.press(.character(letter)) }

        controller.insertEmoji("🐈")

        XCTAssertEqual(target.text, "🐈")
        XCTAssertEqual(controller.overlay, .emojiSearch)
        XCTAssertEqual(controller.emojiQuery, "cat")
    }

    /// The query belongs to one open search. Leaving it set would reopen the box
    /// on yesterday's word and hold 60 result strings alive for the session.
    func testLeavingSearchClearsTheQueryAndTheResults() {
        let (controller, _) = controller()
        controller.show(.emojiSearch)
        controller.press(.character("c"))
        XCTAssertFalse(controller.emojiResults.isEmpty)

        controller.show(.emoji)

        XCTAssertEqual(controller.emojiQuery, "")
        XCTAssertEqual(controller.emojiResults, [])
    }

    /// **The Emoji key is the only way back to the letters**, because the category
    /// row deliberately has no `אבג` of its own any more. From either emoji state
    /// it closes the grid.
    func testTheEmojiKeyClosesTheGridFromEitherState() {
        let (controller, _) = controller()

        controller.press(.emoji)
        XCTAssertEqual(controller.overlay, .emoji)
        controller.press(.emoji)
        XCTAssertEqual(controller.overlay, .none)

        controller.show(.emojiSearch)
        controller.press(.emoji)
        XCTAssertEqual(controller.overlay, .none, "the key did not close search")
    }

    /// Both emoji states answer `isEmoji`, which is what the Emoji key's `אבג` cap
    /// and the suggestion bar's tint both read. Against a bare `== .emoji` the cap
    /// reverted to "Emoji" and the tint went out the moment search opened.
    func testBothEmojiStatesReadAsEmoji() {
        XCTAssertTrue(KeyboardOverlay.emoji.isEmoji)
        XCTAssertTrue(KeyboardOverlay.emojiSearch.isEmoji)
        // `.none` is the only negative case left. This also asserted `.aiMenu` and
        // `.dictation`, and both were deleted with the panels they opened — every
        // remaining case of this enum is an emoji one, which is the point of that
        // change rather than a gap in this test.
        XCTAssertFalse(KeyboardOverlay.none.isEmoji)
        XCTAssertFalse(KeyboardOverlay.copyclip.isEmoji)
        XCTAssertFalse(KeyboardOverlay.copyclipSearch.isEmoji)
        XCTAssertTrue(KeyboardOverlay.copyclip.isCopyClip)
        XCTAssertTrue(KeyboardOverlay.copyclipSearch.isCopyClip)
    }

    // MARK: Recents

    /// **The Recent tab reset to the six shipped emoji constantly**, because
    /// `recentEmoji` was a plain `@Published` array with nowhere to go and iOS
    /// tears a keyboard extension down whenever it likes. Asserted through the
    /// store rather than through the controller's own copy: reading back what you
    /// just wrote to a property in memory proves nothing about persistence.
    func testAPickedEmojiIsWrittenToTheStoreImmediately() {
        let store = SharedStore.shared
        let before = store.recentEmoji
        defer { store.recentEmoji = before }

        let controller = KeyboardController(target: MockTextTarget())
        controller.insertEmoji("🦩")

        XCTAssertEqual(store.recentEmoji.first, "🦩")
        XCTAssertEqual(
            store.storedRecentEmoji.first, "🦩",
            "written to the published copy but not to disk")
    }

    /// Most recent first, no duplicates, and bounded — a list that grows without
    /// limit is a Recent tab you have to scroll to use.
    func testRecentsAreMostRecentFirstAndDeduplicated() {
        let store = SharedStore.shared
        let before = store.recentEmoji
        defer { store.recentEmoji = before }

        let controller = KeyboardController(target: MockTextTarget())
        controller.recentEmoji = []
        for emoji in ["🍕", "🐈", "🍕"] { controller.insertEmoji(emoji) }

        XCTAssertEqual(controller.recentEmoji, ["🍕", "🐈"])

        for index in 0..<40 { controller.insertEmoji(EmojiCatalog.all[index]) }
        XCTAssertEqual(controller.recentEmoji.count, KeyboardController.recentEmojiLimit)
    }

    /// **The Recent tab used to re-sort itself under the finger that tapped it.**
    /// Picking the third emoji moved it to the front, so the two beside it slid a
    /// place across and the next tap in the same spot inserted something else —
    /// which is the opposite of what a Recent tab is for. Asserted on the *drawn*
    /// order and on the record separately, because a build that fixed this by
    /// simply not recording the pick would pass half of it.
    func testPickingAnEmojiDoesNotReorderTheGridItWasPickedFrom() {
        let store = SharedStore.shared
        let before = store.recentEmoji
        defer { store.recentEmoji = before }

        let (controller, _) = controller()
        controller.recentEmoji = ["🍕", "🐈", "🎉"]
        controller.show(.emoji)
        XCTAssertEqual(controller.visibleRecentEmoji, ["🍕", "🐈", "🎉"])

        controller.insertEmoji("🎉")

        XCTAssertEqual(
            controller.visibleRecentEmoji, ["🍕", "🐈", "🎉"],
            "the open grid re-sorted around the emoji that was tapped")
        XCTAssertEqual(controller.recentEmoji.first, "🎉", "the pick was not recorded")
        XCTAssertEqual(store.storedRecentEmoji.first, "🎉", "the pick was not persisted")
    }

    /// The other half of freezing it: the new order has to arrive eventually, and
    /// the next opening is when.
    func testTheNextOpeningPicksUpTheNewOrder() {
        let store = SharedStore.shared
        let before = store.recentEmoji
        defer { store.recentEmoji = before }

        let (controller, _) = controller()
        controller.recentEmoji = ["🍕", "🐈", "🎉"]
        controller.show(.emoji)
        controller.insertEmoji("🎉")
        controller.dismissOverlay()

        controller.show(.emoji)

        XCTAssertEqual(controller.visibleRecentEmoji, ["🎉", "🍕", "🐈"])
    }

    /// **The keyboard going away and coming back is a fresh visit, even though
    /// nothing closed the panel.** `overlay` is never reset on the way out, so an
    /// extension instance iOS keeps alive returns with the grid still open — and a
    /// freeze that only lifted on `show(_:)` would leave the emoji picked just
    /// before the dismissal missing from Recents until the user closed the panel
    /// by hand. `KeyboardViewController.viewWillAppear` calls this method, which
    /// is why it is `public`; a `guard !overlay.isEmoji` added to it as a
    /// "safety" check would fail here rather than in six months on a phone.
    func testTheKeyboardComingBackSettlesTheRecentsUnderAStillOpenPanel() {
        let store = SharedStore.shared
        let before = store.recentEmoji
        defer { store.recentEmoji = before }

        let (controller, _) = controller()
        controller.recentEmoji = ["🍕", "🐈", "🎉"]
        controller.show(.emoji)
        controller.insertEmoji("🎉")

        controller.settleRecentEmoji()

        XCTAssertEqual(controller.overlay, .emoji, "the panel closed, which is not the case here")
        XCTAssertEqual(controller.visibleRecentEmoji, ["🎉", "🍕", "🐈"])
    }

    /// The grid and its search box are one visit. Search is opened from the grid
    /// and backspaced out of it again, so re-settling on either leg is the same
    /// shuffle arriving one key later.
    func testOpeningSearchAndComingBackDoesNotReorderTheRecents() {
        let store = SharedStore.shared
        let before = store.recentEmoji
        defer { store.recentEmoji = before }

        let (controller, _) = controller()
        controller.recentEmoji = ["🍕", "🐈", "🎉"]
        controller.show(.emoji)
        controller.insertEmoji("🎉")

        controller.show(.emojiSearch)
        XCTAssertEqual(controller.visibleRecentEmoji, ["🍕", "🐈", "🎉"])

        controller.show(.emoji)
        XCTAssertEqual(controller.visibleRecentEmoji, ["🍕", "🐈", "🎉"])
    }
}
