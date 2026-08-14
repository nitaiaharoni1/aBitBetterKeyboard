import UIKit
import XCTest

@testable import AIKeyboardCore

/// Long-press list and insert. Overlay toggle stays in `CopyClipModeTests`.
@MainActor
final class CopyClipAlternatesTests: XCTestCase {

    private func clip(_ text: String) -> Clip {
        Clip(id: UUID(), text: ClipText(raw: text)!, capturedAt: Date())
    }

    private func makeController(
        clips: [Clip] = [], target: MockTextTarget? = nil
    )
        -> KeyboardController
    {
        let controller = KeyboardController(target: target ?? MockTextTarget())
        controller.clips = clips
        return controller
    }

    private func copyclipKey(
        alternates: [String],
        onPress: @escaping () -> Void = {},
        onAlternate: ((String) -> Void)? = { _ in }
    ) -> KeyView {
        KeyView(
            spec: KeySpec(.copyclip),
            width: 34,
            height: 44,
            language: .english,
            shift: .off,
            copyclipAlternates: alternates,
            onPress: { _, _ in onPress() },
            onAlternate: onAlternate)
    }

    /// Empty ledger is only the rest title. A `count >= 1` gate would light
    /// the popup on letters that have a single character and no accents.
    func testEmptyClipsOfferOnlyTheRestTitleAndNoPopup() {
        let before = SharedStore.shared.copyclipRecord
        defer { SharedStore.shared.copyclipRecord = before }
        let controller = makeController()
        XCTAssertEqual(controller.copyclipAlternates, ["CopyClip"])

        let view = copyclipKey(alternates: controller.copyclipAlternates)
        XCTAssertFalse(view.hasAlternates)
        XCTAssertFalse(view.runsOnLift)
        XCTAssertNil(
            KeyboardView(controller: controller).alternateHandler(for: KeySpec(.copyclip)))
    }

    /// One clip is rest plus that clip. `prefix(5)` without the rest row
    /// would be count 1 and never open a popup.
    func testOneClipOpensThePopup() {
        let before = SharedStore.shared.copyclipRecord
        defer { SharedStore.shared.copyclipRecord = before }
        let controller = makeController(clips: [clip("hello")])
        XCTAssertEqual(controller.copyclipAlternates, ["CopyClip", "hello"])

        let view = copyclipKey(alternates: controller.copyclipAlternates)
        XCTAssertTrue(view.hasAlternates)
        XCTAssertTrue(view.runsOnLift)
    }

    func testSevenClipsOfferTheRestTitleAndTheFirstFiveOnly() {
        let before = SharedStore.shared.copyclipRecord
        defer { SharedStore.shared.copyclipRecord = before }
        let texts = ["n1", "n2", "n3", "n4", "n5", "n6", "n7"]
        let controller = makeController(clips: texts.map(clip))
        XCTAssertEqual(
            controller.copyclipAlternates,
            ["CopyClip", "n1", "n2", "n3", "n4", "n5"])
        XCTAssertFalse(controller.copyclipAlternates.contains("n6"))
        XCTAssertFalse(controller.copyclipAlternates.contains("n7"))
    }

    /// Picking a row inserts and leaves the panel closed. A stale name
    /// writes nothing and still does not open the overlay.
    func testSelectCopyclipInsertsAndLeavesThePanelClosed() {
        let before = SharedStore.shared.copyclipRecord
        defer { SharedStore.shared.copyclipRecord = before }
        let target = MockTextTarget(text: "hi ")
        let known = clip("there")
        let controller = makeController(clips: [known, clip("other")], target: target)

        controller.selectCopyclip(named: "there")
        XCTAssertEqual(target.text, "hi there")
        XCTAssertEqual(controller.overlay, .none, "picking a clip opened the panel")

        controller.selectCopyclip(named: "not in the ledger")
        XCTAssertEqual(target.text, "hi there", "an unknown name wrote into the field")
        XCTAssertEqual(controller.overlay, .none)
    }

    func testCommitAlternateOnCopyClipDoesNotPressTheKey() {
        var pressed = false
        var picked: [String] = []
        let view = copyclipKey(
            alternates: ["CopyClip", "hello"],
            onPress: { pressed = true },
            onAlternate: { picked.append($0) })
        view.commitAlternate("hello")
        XCTAssertFalse(pressed, "commitAlternate replayed the press and would toggle the panel")
        XCTAssertEqual(picked, ["hello"])
    }

    func testALongClipLabelCollapsesAndTruncatesButTheItemStaysTheFullText() {
        let before = SharedStore.shared.copyclipRecord
        defer { SharedStore.shared.copyclipRecord = before }
        let raw = "line one\nline   two\t" + String(repeating: "x", count: 80)
        let controller = makeController(clips: [clip(raw)])
        XCTAssertEqual(controller.copyclipAlternates[1], raw)

        let view = copyclipKey(alternates: controller.copyclipAlternates)
        let label = view.displayLabel(raw)
        XCTAssertFalse(label.contains("\n"))
        XCTAssertLessThan(label.count, raw.count)
        XCTAssertTrue(label.hasSuffix("…"))
        XCTAssertEqual(view.alternateActionLabel(raw), "Insert \(label)")
    }

    func testTheCopyClipPopupGrowsDownAndMarksEachRow() {
        let view = copyclipKey(alternates: ["CopyClip", "hello", "there"])
        XCTAssertTrue(view.alternatesAreStacked)
        XCTAssertEqual(view.alternatesPopupAlignment, .bottom)
        XCTAssertEqual(view.alternatesPopupOffsetY, 34 * 3 + 6)
        XCTAssertEqual(view.stackedItemIcon("CopyClip"), "clipboard")
        XCTAssertEqual(view.stackedItemIcon("hello"), "doc.plaintext")
        XCTAssertNotNil(UIImage(systemName: "clipboard"))
        XCTAssertNotNil(UIImage(systemName: "doc.plaintext"))
        XCTAssertEqual(view.alternateIndex(at: CGPoint(x: 17, y: 51)), 0)
    }
}
