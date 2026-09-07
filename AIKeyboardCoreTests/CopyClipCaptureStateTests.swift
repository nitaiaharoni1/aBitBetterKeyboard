import UIKit
import XCTest

@testable import AIKeyboardCore

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
    func testAutomaticRefreshCapturesTextWithCopyClipClosed() {
        let before = SharedStore.shared.copyclipRecord
        defer { SharedStore.shared.copyclipRecord = before }
        SharedStore.shared.copyclipRecord = CopyclipRecord(clips: [], lastChangeCount: -1)
        let controller = KeyboardController(target: MockTextTarget())

        for text in ["הודעה ראשונה", "הודעה שנייה"] {
            UIPasteboard.general.string = text
            controller.refreshCopyClip(.automatic)
            XCTAssertEqual(controller.clips.first?.text.value, text)
            XCTAssertEqual(controller.lastChangeCount, UIPasteboard.general.changeCount)
        }
        XCTAssertFalse(controller.overlay.isCopyClip)
        XCTAssertEqual(controller.clips.map(\.text.value), ["הודעה שנייה", "הודעה ראשונה"])
        XCTAssertEqual(SharedStore.shared.copyclipRecord.clips, controller.clips)
        XCTAssertEqual(controller.copyclipCaptureState, .automatic)
    }

    @MainActor
    func testUnavailableTextDoesNotMarkTheGenerationCaptured() {
        let before = SharedStore.shared.copyclipRecord
        defer { SharedStore.shared.copyclipRecord = before }
        UIPasteboard.general.image = UIImage(systemName: "circle")
        SharedStore.shared.copyclipRecord = CopyclipRecord(clips: [], lastChangeCount: -1)
        let controller = KeyboardController(target: MockTextTarget())
        controller.refreshCopyClip(.automatic)
        XCTAssertTrue(controller.clips.isEmpty)
        XCTAssertEqual(controller.lastChangeCount, -1)
        XCTAssertNil(controller.attemptedCopyclipGeneration)
    }

    @MainActor
    func testStoppedWatcherDoesNotPerformItsInitialRead() async {
        let before = SharedStore.shared.copyclipRecord
        defer { SharedStore.shared.copyclipRecord = before }
        UIPasteboard.general.string = "must not be captured after stopping"
        SharedStore.shared.copyclipRecord = CopyclipRecord(clips: [], lastChangeCount: -1)
        let controller = KeyboardController(target: MockTextTarget())
        controller.startWatchingPasteboard()
        let watch = controller.copyclipWatchTask
        controller.stopWatchingPasteboard()
        await watch?.value
        XCTAssertTrue(controller.clips.isEmpty)
        XCTAssertNil(controller.attemptedCopyclipGeneration)
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

    // MARK: The target behind the system paste button

    /// **Every assertion here goes through `UIPasteConfigurationSupporting`,
    /// never through the Swift method directly**, because that is the whole
    /// difference between a button that works and the dimmed one that
    /// shipped. `canPasteItemProviders:` is an *optional* requirement, its
    /// Swift spelling is `canPaste(_:)` with no argument label, and the first
    /// version of `CopyClipPasteControl` declared `canPaste(itemProviders:)`
    /// on a bare `NSObject`. That answers correctly when Swift calls it and
    /// is invisible to iOS, which asks the target whether it can paste before
    /// it enables the control — so the one route from a fresh copy into the
    /// ledger was dead while the panel promised "Paste adds it here."
    /// Reached as the protocol member, the old spelling is `nil`.
    @MainActor
    func testThePasteTargetAnswersTheOptionalRequirementIOSActuallyAsks() {
        let target: any UIPasteConfigurationSupporting = PasteControlHost { _, _ in }

        XCTAssertEqual(
            target.canPaste?([NSItemProvider(object: "copied elsewhere" as NSString)]), true,
            "a target that answers nothing here is read as 'cannot paste' and the control never enables"
        )
    }

    /// A copied screenshot reaching the panel at all is the case
    /// `PasteboardReader.holdsText` could not rule out, so the control has to
    /// go quiet on its own rather than offer a paste that can only be empty.
    @MainActor
    func testThePasteTargetRefusesAGenerationThatIsNotText() throws {
        let target: any UIPasteConfigurationSupporting = PasteControlHost { _, _ in }
        let image = try XCTUnwrap(UIImage(systemName: "circle"))

        XCTAssertEqual(
            target.canPaste?([NSItemProvider(object: image)]), false,
            "a blanket true would offer a paste button over a copied image")
    }

    /// The two halves `UIPasteControl` needs from its target, and the reason
    /// the target is a `UIView` rather than a coordinator object: the only
    /// default implementation of `canPasteItemProviders:` — the one that
    /// matches the board against `pasteConfiguration` — lives on
    /// `UIResponder`.
    @MainActor
    func testThePasteTargetIsAResponderCarryingAPlainTextConfiguration() {
        let host = PasteControlHost { _, _ in }

        XCTAssertTrue(
            PasteControlHost.isSubclass(of: UIResponder.self),
            "a target off the responder chain has no pasteConfiguration iOS will read")
        let accepted = host.pasteConfiguration?.acceptableTypeIdentifiers ?? []
        XCTAssertTrue(
            NSString.readableTypeIdentifiersForItemProvider.allSatisfy(accepted.contains),
            "the control is disabled until its target says which types it accepts")
    }
}
