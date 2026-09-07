import UIKit
import XCTest

@testable import AIKeyboardCore

// MARK: - The editor's arithmetic

@MainActor
final class LayoutEditorTests: XCTestCase {

    internal func editor(_ layout: KeyboardCustomization = .default) -> LayoutEditorModel {
        LayoutEditorModel(layout: layout)
    }

    // MARK: Moving

    func testMovingAKeyChangesItsPosition() {
        let model = editor()
        let movable = model.draft.bottomRow.first { $0.action == .punctuation }!
        let before = model.draft.bottomRow.firstIndex(of: movable)!
        model.move(movable, by: -1)
        XCTAssertEqual(model.draft.bottomRow.firstIndex(of: movable), before - 1)
    }

    /// Out of range is a no-op rather than a clamp: Move left on the leftmost key
    /// should do nothing, not silently re-anchor it.
    func testMovingPastTheEndDoesNothing() {
        let model = editor()
        let order = model.draft.bottomRow
        model.move(order.first!, by: -1)
        model.move(order.last!, by: 1)
        XCTAssertEqual(model.draft.bottomRow, order)
        XCTAssertFalse(model.canUndo, "a no-op must not leave an undo step")
    }

    func testDroppingAKeyAtAnIndexPutsItThere() {
        let model = editor()
        let ret = model.draft.bottomRow.last!
        model.move(ret, to: .bottom, at: 0)
        XCTAssertEqual(model.draft.bottomRow.first, ret)
    }

    func testDroppingIntoAnotherRowMovesItBetweenThem() {
        let model = editor()
        model.draft.cursorRow = KeyboardCustomization.actionRow
        let movable = model.draft.bottomRow.first { $0.action == .punctuation }!
        model.move(movable, to: .cursor, at: 0)
        XCTAssertFalse(model.draft.bottomRow.contains(movable))
        XCTAssertEqual(model.draft.cursorRow.first, movable)
    }

    func testDroppingPastTheEndAppendsRatherThanCrashing() {
        let model = editor()
        let first = model.draft.bottomRow[0]
        model.move(first, to: .bottom, at: 99)
        XCTAssertEqual(model.draft.bottomRow.last, first)
    }

    /// Pure arithmetic, so it is testable without a gesture. The midpoint of each
    /// key is the boundary, so a finger past the middle means "after it".
    func testTheInsertionIndexFollowsTheFinger() {
        let frames: [CGRect] = [
            CGRect(x: 0, y: 0, width: 40, height: 40),
            CGRect(x: 44, y: 0, width: 40, height: 40),
            CGRect(x: 88, y: 0, width: 40, height: 40)
        ]
        XCTAssertEqual(LayoutEditorModel.insertionIndex(at: 5, in: frames), 0)
        XCTAssertEqual(LayoutEditorModel.insertionIndex(at: 35, in: frames), 1)
        XCTAssertEqual(LayoutEditorModel.insertionIndex(at: 79, in: frames), 2)
        XCTAssertEqual(LayoutEditorModel.insertionIndex(at: 200, in: frames), 3)
        XCTAssertEqual(LayoutEditorModel.insertionIndex(at: 0, in: []), 0)
    }

    // MARK: Removing

    /// **Return, not the globe.** This reached for `.globe` in the shipped
    /// default and force-unwrapped it; no preset has placed that key since the slot
    /// went to `.emoji`, so the unwrap was nil and it *crashed the test runner*
    /// rather than failing. The globe is also no longer something the editor
    /// refuses — `KeyboardController.apply(_:)` puts it back when the device needs
    /// one, so the validator has no opinion left. Return is an essential that is
    /// really in the row and really refused.
    func testRemovingAnEssentialIsRefused() {
        let model = editor()
        let ret = model.draft.bottomRow.first { $0.action == .ret }!
        model.remove(ret)
        XCTAssertTrue(model.draft.bottomRow.contains(ret))
    }

    func testRemovingAnOrdinaryKeyWorks() {
        let model = editor()
        let movable = model.draft.bottomRow.first { $0.action == .punctuation }!
        model.remove(movable)
        XCTAssertFalse(model.draft.bottomRow.contains(movable))
    }

    func testRemovingTheSelectedKeyClearsTheSelection() {
        let model = editor()
        let movable = model.draft.bottomRow.first { $0.action == .punctuation }!
        model.selection = movable
        model.remove(movable)
        XCTAssertNil(model.selection)
    }

    // MARK: Presets

    func testEditingClearsThePresetAndKeepsBasedOn() {
        let model = editor()
        model.apply(preset: LayoutPreset.named("power")!)
        XCTAssertEqual(model.draft.preset, "power")
        model.add(.text("!"), to: .bottom)
        XCTAssertNil(model.draft.preset)
        XCTAssertEqual(model.draft.basedOn, "power")
    }

    func testResetGoesBackToTheBasePreset() {
        let model = editor()
        model.apply(preset: LayoutPreset.named("power")!)
        model.add(.text("!"), to: .bottom)
        model.reset()
        XCTAssertEqual(model.draft, LayoutPreset.named("power")!.customization)
    }

    /// Editing back to exactly the preset makes it that preset again, so the strip
    /// re-highlights rather than sitting on a stale "Custom".
    func testUndoingBackToThePresetRestoresItsName() {
        let model = editor()
        model.apply(preset: LayoutPreset.named("roomy")!)
        model.add(.text("!"), to: .bottom)
        XCTAssertNil(model.draft.preset)
        model.undo()
        XCTAssertEqual(model.draft.preset, "roomy")
    }

    // MARK: Undo

    func testUndoStepsBackOneEdit() {
        let model = editor()
        let before = model.draft
        model.add(.text("!"), to: .bottom)
        XCTAssertTrue(model.canUndo)
        model.undo()
        XCTAssertEqual(model.draft, before)
        XCTAssertFalse(model.canUndo)
    }

    func testUndoIsCappedAndKeepsTheMostRecent() {
        let model = editor()
        for index in 0..<40 { model.add(.text("\(index)"), to: .bottom) }
        var steps = 0
        while model.canUndo, steps < 100 {
            model.undo()
            steps += 1
        }
        XCTAssertEqual(steps, LayoutEditorModel.undoLimit)
    }

    func testUndoDropsASelectionTheStepRemoved() {
        let model = editor()
        model.add(.text("!"), to: .bottom)
        model.selection = model.draft.bottomRow.last
        model.undo()
        XCTAssertNil(model.selection)
    }

    // MARK: Width and action

    func testWidthIsClamped() {
        let model = editor()
        let key = model.draft.bottomRow[0]
        model.setWidth(.units(99), for: key)
        XCTAssertEqual(
            model.draft.bottomRow.first { $0.id == key.id }?.width,
            .units(SlotWidth.maximumUnits))
    }

    func testChangingAnActionKeepsTheKeysIdentity() {
        let model = editor()
        let key = model.draft.bottomRow.first { $0.action == .punctuation }!
        model.setAction(.emoji, for: key)
        XCTAssertEqual(model.draft.bottomRow.first { $0.id == key.id }?.action, .emoji)
    }

    // MARK: Labels

    /// The switch writes an explicit answer and is one undo step, like every
    /// other edit.
    func testTheLabelSwitchIsStoredAndUndoable() {
        let model = editor()
        model.draft.cursorRow = KeyboardCustomization.actionRow
        let fix = model.draft.cursorRow.first { $0.action == .fix }!
        XCTAssertNil(fix.showsLabel, "the shipped layout should carry no opinion")

        model.setShowsLabel(false, for: fix)
        XCTAssertEqual(model.draft.cursorRow.first { $0.id == fix.id }?.showsLabel, false)
        model.undo()
        XCTAssertNil(model.draft.cursorRow.first { $0.id == fix.id }?.showsLabel)
    }

    /// **Only the six keys that draw a name have one to hide.** The return key's
    /// cap *is* its label, so a switch on it would produce a blank key — the
    /// refusal is in the model rather than only in the menu that draws it,
    /// because `perform` and the menu are two callers.
    func testAKeyWithNoNameUnderItsGlyphRefusesTheSwitch() {
        let model = editor()
        let ret = model.draft.bottomRow.first { $0.action == .ret }!
        model.setShowsLabel(false, for: ret)
        XCTAssertNil(model.draft.bottomRow.first { $0.id == ret.id }?.showsLabel)
        XCTAssertFalse(model.canUndo, "a refused edit must not leave an undo step")
        // And it reads as off however wide it is. Without the guard this is the
        // *position* rule's answer — true, on a key that draws an arrow and no
        // word — which is a switch offering to hide a label that does not exist.
        XCTAssertFalse(model.drawsLabel(ret, drawnWidth: KeyView.captionMinimumWidth + 20))
    }

    /// **What the switch shows is what the canvas is drawing**, which is why it
    /// takes the measured width: the same key with the same stored value answers
    /// differently at one unit and at three, and a switch reading "on" over a key
    /// with no word on it is the defect this argument exists for.
    func testTheLabelSwitchReportsWhatTheKeyIsActuallyDrawing() {
        let model = editor()
        // Emoji is appended rather than looked up: it left the action row when it
        // traded seats with the gear, and `first { $0.action == .emoji }!` on a
        // row that no longer holds it is a nil force-unwrap, which *kills the
        // runner* rather than failing one case. The rule under test is still about
        // Emoji, so the fixture puts one there.
        model.draft.cursorRow =
            KeyboardCustomization.actionRow + [SlotSpec(action: .emoji, width: .fill)]
        let fix = model.draft.cursorRow.first { $0.action == .fix }!
        let emoji = model.draft.cursorRow.first { $0.action == .emoji }!
        let wide = KeyView.captionMinimumWidth + 20
        let narrow = KeyView.captionMinimumWidth - 20

        XCTAssertTrue(model.drawsLabel(fix, drawnWidth: wide))
        XCTAssertFalse(model.drawsLabel(fix, drawnWidth: narrow), "too narrow to name itself")
        XCTAssertFalse(model.drawsLabel(emoji, drawnWidth: wide), "a glyph in the action row")

        model.setShowsLabel(true, for: emoji)
        let asked = model.draft.cursorRow.first { $0.id == emoji.id }!
        XCTAssertTrue(model.drawsLabel(asked, drawnWidth: narrow), "an explicit yes beats both")
    }

    /// **The selection is a copy, and the inspector reads its width off that
    /// copy.** Without the re-resolve, moving the slider once left the inspector
    /// showing the old value and every later drag started from it.
    func testTheSelectionIsRefreshedAfterAnEdit() {
        let model = editor()
        let key = model.draft.bottomRow[0]
        model.selection = key
        model.setWidth(.units(2), for: key)
        XCTAssertEqual(model.selection?.width, .units(2))
    }

    // MARK: Rows

    // **`testTurningTheExtraRowOnSeedsItWithTheShippedActionRow` is deleted with
    // the switch it covered.** `setExtraRow(enabled:)` is gone — see
    // `LayoutGeometrySection` for why a control that emptied the action row in
    // one tap was the wrong affordance — and rewriting the test against a direct
    // `draft.cursorRow` write left it asserting the value it had just assigned.
    //
    // `testTheExtraRowIsListedOnlyWhenItExists` went the same way, and so did
    // `LayoutEditorModel.visibleRows` underneath it. Nothing in the app listed
    // rows any more once the editor's row sections were replaced by the canvas,
    // so the property's only remaining caller was that test: a test keeping its
    // own subject alive, which reads to the next person as an editor feature
    // that still exists.

    func testRowKindFindsAKeyInEveryRow() {
        let model = editor()
        model.draft.cursorRow = KeyboardCustomization.actionRow
        // **The bar ends are empty in the shipped default now** — the emoji key,
        // the one-tap rewrite and the AI menu (since deleted; its actions each
        // got their own key) all moved into the action row — so this has to put
        // something in them rather than index into them. It used to index
        // straight in and crashed the whole runner when the default changed,
        // which took 367 later tests with it and reported as
        // `** TEST FAILED **` with no failing assertion anywhere. `.reply`
        // stands in for the old sparkle: any real action proves the point, and
        // Reply is one the catalogue still has.
        model.add(.emoji, to: .barLeading)
        model.add(.reply, to: .barTrailing)
        XCTAssertEqual(model.rowKind(of: model.draft.bottomRow[0]), .bottom)
        XCTAssertEqual(model.rowKind(of: model.draft.cursorRow[0]), .cursor)
        XCTAssertEqual(model.rowKind(of: model.draft.barLeading[0]), .barLeading)
        XCTAssertEqual(model.rowKind(of: model.draft.barTrailing[0]), .barTrailing)
        XCTAssertNil(model.rowKind(of: SlotSpec(action: .space)))
    }

    func testTheBarOffersItsOwnNarrowerCatalogue() {
        let model = editor()
        XCTAssertEqual(model.catalogue(for: .barLeading), SuggestionBar.barCatalogue)
        XCTAssertEqual(model.catalogue(for: .bottom), SlotAction.catalogue)
    }

    func testIssuesTrackTheDraft() {
        let model = editor()
        XCTAssertTrue(model.isUsable)
        // Reached past `remove`, which refuses this, the way a layout decoded from
        // another build would arrive.
        model.draft.bottomRow.removeAll { $0.action == .space }
        XCTAssertFalse(model.isUsable)
        XCTAssertTrue(model.issues.contains { $0.kind == .missingSpace })
    }

    func testGeometrySettersClamp() {
        let model = editor()
        model.setKeyHeight(999)
        XCTAssertEqual(model.draft.geometry.keyHeight, LayoutGeometry.keyHeightRange.upperBound)
        model.setRowSpacing(0)
        XCTAssertEqual(model.draft.geometry.rowSpacing, LayoutGeometry.rowSpacingRange.lowerBound)
        model.setReach(.right)
        XCTAssertEqual(model.draft.geometry.reach, .right)
    }

    /// **Each band clamps and writes only itself.** The default ships all three
    /// equal, so a setter that ignored its `band:` argument and wrote the letters
    /// every time would agree with a test that only read back the band it had
    /// just set. This reads back the other two as well.
    func testEachRowBandTakesItsOwnHeightAndLeavesTheOthers() {
        for band in LayoutGeometry.RowBand.allCases {
            let model = editor()
            let before = LayoutGeometry.RowBand.allCases.map { model.draft.geometry.height($0) }
            model.setKeyHeight(999, for: band)

            XCTAssertEqual(
                model.draft.geometry.height(band), LayoutGeometry.keyHeightRange.upperBound,
                "\(band.rawValue) did not clamp")
            for (index, other) in LayoutGeometry.RowBand.allCases.enumerated() where other != band {
                XCTAssertEqual(
                    model.draft.geometry.height(other), before[index],
                    "setting \(band.rawValue) also moved \(other.rawValue)")
            }
        }
    }

    /// The undo stack covers a row height like any other edit, and the band it
    /// restores is the band that moved.
    func testUndoingARowHeightRestoresThatRow() {
        let model = editor()
        let before = model.draft.geometry.height(.action)
        model.setKeyHeight(LayoutGeometry.keyHeightRange.upperBound, for: .action)
        XCTAssertNotEqual(model.draft.geometry.height(.action), before)
        model.undo()
        XCTAssertEqual(model.draft.geometry.height(.action), before)
    }

    // MARK: Reading the drawn keyboard
    //
    // **These two had no test at all.** They were `static` on `LayoutView` with a
    // comment saying they were static "so `LayoutFrameMappingTests` can drive
    // it", and that file has never existed — the app target has no unit-test
    // bundle for it to live in. They decide which drawn key belongs to which
    // slot and which rows refuse a drop, so between them they are the whole
    // drag system's view of the screen.

    /// **The `#uuid` suffix is the identity, and the prefix is not.** Two commas
    /// on one row compile to `char-,#aaaa…` and `char-,#bbbb…`; matching on the
    /// prefix would map both to whichever slot was asked for first, and dragging
    /// either would move the other.
    func testTwoKeysWithTheSameActionMapToTheirOwnFrames() {
        let first = SlotSpec(action: .text(","))
        let second = SlotSpec(action: .text(","))
        let frames = [
            "char-,#\(first.id.uuidString.prefix(8))": CGRect(x: 0, y: 0, width: 30, height: 40),
            "char-,#\(second.id.uuidString.prefix(8))": CGRect(x: 40, y: 0, width: 30, height: 40)
        ]

        let mapped = LayoutEditorModel.mapFrames(frames, to: [first, second])

        XCTAssertEqual(mapped[first.id]?.minX, 0)
        XCTAssertEqual(
            mapped[second.id]?.minX, 40,
            "both commas mapped to one frame: the id prefix is not the identity")
    }

    /// A slot the keyboard did not draw has no frame rather than a zero one: a
    /// `CGRect.zero` would be a legal drop target at the top-left corner.
    func testASlotTheKeyboardDidNotDrawIsAbsentRatherThanZero() {
        let drawn = SlotSpec(action: .space)
        let missing = SlotSpec(action: .ret)
        let frames = [
            "space#\(drawn.id.uuidString.prefix(8))": CGRect(x: 0, y: 0, width: 100, height: 40)
        ]

        let mapped = LayoutEditorModel.mapFrames(frames, to: [drawn, missing])

        XCTAssertEqual(mapped.count, 1)
        XCTAssertNil(mapped[missing.id])
    }

    /// Keys with no `#uuid` are the rows extracted from Apple's data, and they
    /// merge per drawn row. The two `q`/`a` rects here overlap on purpose: a
    /// grouped band is one double-height row, and reporting it as two would let a
    /// drop land inside the letters.
    func testFrozenBandsMergeOverlappingRowsAndIgnoreCustomKeys() {
        let custom = SlotSpec(action: .space)
        let frames: [String: CGRect] = [
            "char-q": CGRect(x: 0, y: 0, width: 30, height: 40),
            "char-a": CGRect(x: 0, y: 20, width: 30, height: 40),
            "char-z": CGRect(x: 0, y: 100, width: 30, height: 40),
            "space#\(custom.id.uuidString.prefix(8))": CGRect(
                x: 0, y: 200, width: 100, height: 40)
        ]

        let bands = LayoutEditorModel.frozenBands(from: frames).sorted { $0.lowerBound < $1.lowerBound }

        XCTAssertEqual(bands.count, 2, "the overlapping q/a rects are one drawn row")
        XCTAssertEqual(bands.first?.lowerBound, 0)
        XCTAssertEqual(bands.first?.upperBound, 60, "the merged band is the union, not the first rect")
        XCTAssertEqual(bands.last?.lowerBound, 100)
        XCTAssertFalse(
            bands.contains { $0.contains(220) },
            "a key the user placed was reported as frozen, so it could not be dragged")
    }

    // MARK: Drag session

    /// Five midpoint updates must not touch `draft`. One undo after drop restores
    /// the start, and the stack is empty.
    ///
    /// **The sweep ends past the last key's midpoint, not on it.** `boardGeometry`
    /// puts key *n* at `n * 44` with width 40, so the last midpoint is exactly
    /// 196 — and `insertionIndex` counts `x > midX`, which 196 is not. The key
    /// under test starts at index 3 of five, so a sweep that stops one short of
    /// the end walks it 3 → 0 → 1 → 2 → 3 and hands back the order it began
    /// with: `draft` was untouched and the stack was one step, both true, while
    /// the assertion that the *preview* moved was false at the one moment it is
    /// read. 210 is past the last cap rather than on its centre line.
    func testAFiveMidpointDragIsOneUndoStep() {
        let model = editor()
        let key = model.draft.bottomRow.first { $0.action == .punctuation }!
        let start = model.draft
        model.beginDrag(key)
        for x in [20.0, 64.0, 108.0, 152.0, 210.0] {
            model.updateDrag(at: CGPoint(x: x, y: 120), in: boardGeometry(model))
        }
        XCTAssertEqual(model.draft, start)
        XCTAssertNotEqual(model.displayed.bottomRow.map(\.id), start.bottomRow.map(\.id))
        model.endDrag(for: key.id)
        model.undo()
        XCTAssertEqual(model.draft, start)
        XCTAssertFalse(model.canUndo)
    }

    func testDroppingOverTheLettersChangesNothing() {
        let model = editor()
        let key = model.draft.bottomRow.first { $0.action == .punctuation }!
        let start = model.draft
        model.beginDrag(key)
        model.updateDrag(at: CGPoint(x: 100, y: 10), in: boardGeometry(model))
        XCTAssertNil(model.session?.proposed)
        model.endDrag(for: key.id)
        XCTAssertEqual(model.draft, start)
        XCTAssertFalse(model.canUndo)
    }

    /// The extra row lands on the top letter row, so the well overlaps that
    /// frozen band on purpose. A drop there creates the row. A drop on the
    /// letters below it is still ignored.

}
