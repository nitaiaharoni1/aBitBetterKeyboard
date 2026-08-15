import UIKit
import XCTest

@testable import AIKeyboardCore

/// The decision behind `UIPasteControl`: which of automatic capture, the
/// paste control, or neither the panel draws. `ClipboardHistoryTests` below
/// need no live pasteboard at all — that is the point of the pure function —
/// and the `KeyboardController` half proves the two things a pasteboard test
/// actually can: that `.userAsked` stops short of reading a text generation,
/// and that the capture that does land came from the control's own argument
/// rather than a second read of the board.
final class CopyClipCaptureStateTests: XCTestCase {

    // MARK: Pure decision

    func testUnchangedCountIsAutomaticRegardlessOfWhatTheBoardHolds() {
        XCTAssertEqual(
            ClipboardHistory.captureState(changeCount: 4, lastChangeCount: 4, holdsText: true),
            .automatic,
            "a build that skipped the equality check would answer .control here")
        XCTAssertEqual(
            ClipboardHistory.captureState(changeCount: 4, lastChangeCount: 4, holdsText: false),
            .automatic)
    }

    func testANewTextGenerationOffersTheControl() {
        XCTAssertEqual(
            ClipboardHistory.captureState(changeCount: 5, lastChangeCount: 4, holdsText: true),
            .control,
            "a build that read the board here rather than deferring to a tap has nothing to test against, but this is the branch that must not silently become .automatic or .neither"
        )
    }

    func testANewNonTextGenerationOffersNeither() {
        XCTAssertEqual(
            ClipboardHistory.captureState(changeCount: 5, lastChangeCount: 4, holdsText: false),
            .neither,
            "an image or a file can never become a clip, so this must not be .control")
    }

    func testANeverCapturedLedgerIsJustAnotherNewGeneration() {
        // `CopyclipRecord.empty` seeds `lastChangeCount` at -1. That sentinel
        // needs no special case: it is simply unequal to any real generation.
        XCTAssertEqual(
            ClipboardHistory.captureState(changeCount: 0, lastChangeCount: -1, holdsText: true),
            .control)
        XCTAssertEqual(
            ClipboardHistory.captureState(changeCount: 0, lastChangeCount: -1, holdsText: false),
            .neither)
    }

    // MARK: KeyboardController integration

    @MainActor
    func testUserAskedLeavesANewTextGenerationPendingRatherThanReadingIt() {
        let before = SharedStore.shared.copyclipRecord
        defer { SharedStore.shared.copyclipRecord = before }
        // Written by this process, so reading it back in this test never
        // prompts; what is under test is whether the keyboard's own code
        // reads it, not what iOS would do about that read.
        UIPasteboard.general.string = "fresh from another app"
        SharedStore.shared.copyclipRecord = CopyclipRecord(clips: [], lastChangeCount: -1)

        let controller = KeyboardController(target: MockTextTarget())
        controller.refreshCopyClip(.userAsked)

        XCTAssertEqual(
            controller.clips, [],
            "a build that still auto-captures on open put the text straight into the ledger")
        XCTAssertEqual(
            controller.copyclipCaptureState, .control,
            "the panel has nothing to offer a build that forgot to leave the cursor pending")
        XCTAssertNotEqual(
            controller.lastChangeCount, UIPasteboard.general.changeCount,
            "the cursor must not advance until a tap through the control grants the read")
    }

    @MainActor
    func testUserAskedSkipsANonTextGenerationAndAdvancesThePastCursor() {
        let before = SharedStore.shared.copyclipRecord
        defer { SharedStore.shared.copyclipRecord = before }
        UIPasteboard.general.image = UIImage(systemName: "circle")
        SharedStore.shared.copyclipRecord = CopyclipRecord(clips: [], lastChangeCount: -1)

        let controller = KeyboardController(target: MockTextTarget())
        controller.refreshCopyClip(.userAsked)

        XCTAssertEqual(
            controller.copyclipCaptureState, .automatic,
            "a copied image must not be left offering a control that can only ever be empty")
        XCTAssertEqual(
            controller.lastChangeCount, UIPasteboard.general.changeCount,
            "a generation that can never become a clip must not be re-examined on the next open")
    }

    @MainActor
    func testCaptureFromPasteControlUsesItsOwnArgumentNotTheLiveBoard() {
        let before = SharedStore.shared.copyclipRecord
        defer { SharedStore.shared.copyclipRecord = before }
        // Deliberately different from what is captured, so a build that
        // quietly fell back to `UIPasteboard.general.string` is caught.
        UIPasteboard.general.string = "whatever happens to be on the board"
        SharedStore.shared.copyclipRecord = CopyclipRecord(clips: [], lastChangeCount: -1)

        let controller = KeyboardController(target: MockTextTarget())
        controller.captureFromPasteControl("delivered by the paste control")

        XCTAssertEqual(
            controller.clips.map(\.text.value), ["delivered by the paste control"],
            "capture must use the text the control handed it, not re-read the board")
        XCTAssertEqual(
            controller.lastChangeCount, UIPasteboard.general.changeCount,
            "capture did not move the cursor, so the same generation would be offered again")
        XCTAssertEqual(controller.copyclipCaptureState, .automatic)
    }
}
