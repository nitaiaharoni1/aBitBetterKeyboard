import UIKit
import XCTest

@testable import AIKeyboardCore

/// Overlay toggle and insert. Assertions reject the builds that leave the
/// overlay empty, close on insert, or write into a closed panel.
@MainActor
final class CopyClipModeTests: XCTestCase {

    func testPressOpensAndClosesCopyClip() {
        let before = SharedStore.shared.copyclipRecord
        defer { SharedStore.shared.copyclipRecord = before }
        let controller = KeyboardController(target: MockTextTarget())
        XCTAssertEqual(controller.overlay, .none)
        controller.press(.copyclip)
        XCTAssertEqual(controller.overlay, .copyclip, "the key did not open CopyClip")
        XCTAssertFalse(controller.overlay.isEmoji)
        controller.press(.copyclip)
        XCTAssertEqual(controller.overlay, .none, "the key did not close CopyClip")
        XCTAssertTrue(KeyboardOverlay.copyclip.showsActionRow)
        XCTAssertFalse(KeyboardOverlay.copyclip.showsLetterKeys)
        XCTAssertTrue(KeyboardOverlay.copyclipSearch.isCopyClip)
        XCTAssertTrue(KeyboardOverlay.copyclipSearch.showsLetterKeys)
        XCTAssertFalse(KeyboardOverlay.copyclipSearch.showsActionRow)
    }

    func testInsertClipWritesTheDocumentAndLeavesThePanelOpen() {
        let before = SharedStore.shared.copyclipRecord
        defer { SharedStore.shared.copyclipRecord = before }
        let target = MockTextTarget(text: "hi ")
        let controller = KeyboardController(target: target)
        controller.press(.copyclip)
        XCTAssertEqual(controller.overlay, .copyclip)

        let clip = Clip(id: UUID(), text: ClipText(raw: "there")!, capturedAt: Date())
        controller.insertClip(clip)

        XCTAssertEqual(target.text, "hi there", "insert did not write the clip")
        XCTAssertEqual(
            controller.overlay, .copyclip, "insert closed the panel the way a mode switch would")
    }

    func testClearKeepsTheCursorOnTheStore() {
        let before = SharedStore.shared.copyclipRecord
        defer { SharedStore.shared.copyclipRecord = before }
        let controller = KeyboardController(target: MockTextTarget())
        let clip = Clip(id: UUID(), text: ClipText(raw: "hello")!, capturedAt: Date())
        controller.clips = [clip]
        controller.lastChangeCount = 7
        controller.clearClips()
        XCTAssertEqual(controller.clips, [], "Clear left a clip in memory")
        XCTAssertEqual(controller.lastChangeCount, 7, "Clear moved the pasteboard cursor")
        XCTAssertEqual(SharedStore.shared.copyclipRecord.clips, [])
        XCTAssertEqual(
            SharedStore.shared.copyclipRecord.lastChangeCount, 7,
            "Clear lost the cursor, so the current board would come back after a kill")
    }

    /// Letters build the query and leave the message alone. The broken version
    /// typed into whatever the user was writing, the same bug emoji search had.
    func testSearchTypingGoesToTheQueryAndNotToTheDocument() {
        let before = SharedStore.shared.copyclipRecord
        defer { SharedStore.shared.copyclipRecord = before }
        let target = MockTextTarget(text: "hello")
        let controller = KeyboardController(target: target)
        controller.shift = .off
        controller.show(.copyclipSearch)
        let clip = Clip(id: UUID(), text: ClipText(raw: "meeting notes")!, capturedAt: Date())
        controller.clips = [clip]

        for letter in ["m", "e", "e"] { controller.press(.character(letter)) }

        XCTAssertEqual(controller.copyclipQuery, "mee")
        XCTAssertEqual(target.text, "hello", "the query was typed into the message")
        XCTAssertEqual(controller.copyclipResults.map(\.id), [clip.id])
    }

    func testSearchBackspaceOnAnEmptyQueryReturnsToTheListWithoutEatingTheMessage() {
        let before = SharedStore.shared.copyclipRecord
        defer { SharedStore.shared.copyclipRecord = before }
        let target = MockTextTarget(text: "hello")
        let controller = KeyboardController(target: target)
        controller.shift = .off
        controller.show(.copyclipSearch)
        controller.press(.character("a"))
        controller.press(.backspace)
        XCTAssertEqual(controller.copyclipQuery, "")
        XCTAssertEqual(target.text, "hello")

        SharedStore.shared.haptics = true
        let impacts = Feedback.impactCount
        controller.press(.backspace)
        XCTAssertEqual(controller.overlay, .copyclip)
        XCTAssertEqual(target.text, "hello", "backspace fell through to the document")
        XCTAssertEqual(
            Feedback.impactCount, impacts + 1,
            "empty-query backspace buzzed twice: keyPress then show")
    }

    /// **Writes only into the suite, behind the published copy's back**, the
    /// same shape as `FeedbackSettingsTests`. `refreshCopyClip` used to re-seed
    /// from `copyclipRecord`, so a Clear the app wrote never reached an
    /// extension iOS had already built, and the next pasteboard change wrote
    /// the old list back.
    func testRefreshSeesAClearWrittenInTheOtherProcess() throws {
        let before = SharedStore.shared.copyclipRecord
        defer { SharedStore.shared.copyclipRecord = before }

        let clip = Clip(id: UUID(), text: ClipText(raw: "hello")!, capturedAt: Date())
        SharedStore.shared.copyclipRecord = CopyclipRecord(clips: [clip], lastChangeCount: 1)
        let controller = KeyboardController(target: MockTextTarget())
        XCTAssertEqual(controller.clips.map(\.text.value), ["hello"])

        let cleared = CopyclipRecord(
            clips: [], lastChangeCount: UIPasteboard.general.changeCount)
        let data = try XCTUnwrap(JSONEncoder().encode(cleared))
        SharedStore.shared.userDefaults.set(data, forKey: SharedStore.Key.copyclipHistory)
        XCTAssertFalse(
            SharedStore.shared.copyclipRecord.clips.isEmpty,
            "the published copy must stay stale, or this proves nothing")
        XCTAssertTrue(SharedStore.shared.storedCopyclipRecord.clips.isEmpty)

        controller.refreshCopyClip()
        XCTAssertEqual(
            controller.clips, [],
            "Clear in the app came back the next time the keyboard snapshotted")
    }

    func testInsertFromSearchLeavesSearchOpen() {
        let before = SharedStore.shared.copyclipRecord
        defer { SharedStore.shared.copyclipRecord = before }
        let target = MockTextTarget(text: "hi ")
        let controller = KeyboardController(target: target)
        controller.show(.copyclipSearch)
        let clip = Clip(id: UUID(), text: ClipText(raw: "there")!, capturedAt: Date())
        controller.clips = [clip]
        controller.setCopyclipQuery("th")
        controller.insertClip(clip)

        XCTAssertEqual(target.text, "hi there")
        XCTAssertEqual(controller.overlay, .copyclipSearch, "insert closed search")
        XCTAssertEqual(controller.copyclipQuery, "th")
    }

    func testTheCopyClipKeyClosesFromEitherState() {
        let before = SharedStore.shared.copyclipRecord
        defer { SharedStore.shared.copyclipRecord = before }
        let controller = KeyboardController(target: MockTextTarget())
        controller.press(.copyclip)
        XCTAssertEqual(controller.overlay, .copyclip)
        controller.show(.copyclipSearch)
        controller.press(.copyclip)
        XCTAssertEqual(controller.overlay, .none, "the key did not close search")
    }

    /// **The keyboard coming up must not read what is on the pasteboard**, because
    /// that read is what raises iOS's "Allow Paste?" alert, and it was being spent
    /// on every focused field in every host app. There is no way to observe the
    /// alert from a test, so the assertion is on the only consequence a test can
    /// see: a passive refresh over a board this ledger has never reconciled leaves
    /// the ledger empty. The old build captured on any refresh at all, so it fails
    /// on the first `XCTAssertEqual` — and the `.userAsked` half below is what
    /// stops a build that simply stopped capturing from passing.
    func testAppearingDoesNotReadThePasteboardAndOpeningCopyClipDoes() {
        let before = SharedStore.shared.copyclipRecord
        defer { SharedStore.shared.copyclipRecord = before }
        // Written by this process, so reading it back here never prompts. What
        // is under test is *whether* it is read, not what iOS does about it.
        UIPasteboard.general.string = "board text nobody asked for"
        SharedStore.shared.copyclipRecord = CopyclipRecord(clips: [], lastChangeCount: -1)

        let controller = KeyboardController(target: MockTextTarget())
        XCTAssertNotEqual(
            controller.lastChangeCount, UIPasteboard.general.changeCount,
            "the ledger already agrees with the board, so neither half of this proves anything")

        controller.refreshCopyClip()
        XCTAssertEqual(
            controller.clips, [],
            "the keyboard read the pasteboard just for coming up, which is the Allow Paste alert")

        controller.refreshCopyClip(.userAsked)
        XCTAssertEqual(
            controller.clips.map(\.text.value), ["board text nobody asked for"],
            "asking for CopyClip did not capture, so the feature no longer captures at all")
    }

    /// The panel-open path is the one caller of `.userAsked`, so a `show(_:)` that
    /// still refreshes passively would leave a just-copied string out of the list
    /// the user opened the panel to see.
    func testOpeningTheCopyClipPanelIsWhatCaptures() {
        let before = SharedStore.shared.copyclipRecord
        defer { SharedStore.shared.copyclipRecord = before }
        UIPasteboard.general.string = "captured on open"
        SharedStore.shared.copyclipRecord = CopyclipRecord(clips: [], lastChangeCount: -1)

        let controller = KeyboardController(target: MockTextTarget())
        XCTAssertEqual(controller.clips, [], "construction read the board")

        controller.press(.copyclip)
        XCTAssertEqual(controller.overlay, .copyclip)
        XCTAssertEqual(
            controller.clips.map(\.text.value), ["captured on open"],
            "opening the panel did not read the board")
    }

    func testLeavingSearchClearsTheQueryAndTheResults() {
        let before = SharedStore.shared.copyclipRecord
        defer { SharedStore.shared.copyclipRecord = before }
        let controller = KeyboardController(target: MockTextTarget())
        controller.show(.copyclipSearch)
        let clip = Clip(id: UUID(), text: ClipText(raw: "notes")!, capturedAt: Date())
        controller.clips = [clip]
        controller.setCopyclipQuery("no")
        XCTAssertFalse(controller.copyclipResults.isEmpty)

        controller.show(.copyclip)

        XCTAssertEqual(controller.copyclipQuery, "")
        XCTAssertEqual(controller.copyclipResults, [])
    }
}
