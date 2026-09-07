import UIKit
import XCTest

@testable import AIKeyboardCore

extension LayoutEditorTests {
    func testTheExtraRowWellWinsOverTheFrozenBandItOverlaps() {
        let geometry = CanvasGeometry(
            keyFrames: [:],
            rowBands: [.bottom: 200...260],
            trayBand: 300...380,
            extraRowWell: 0...43,
            frozenBands: [0...43, 55...98]
        )
        XCTAssertEqual(
            LayoutEditorModel.dropTarget(
                at: CGPoint(x: 20, y: 20), in: geometry, dragging: nil),
            .board(row: .cursor, index: 0))
        XCTAssertNil(
            LayoutEditorModel.dropTarget(
                at: CGPoint(x: 20, y: 70), in: geometry, dragging: nil))
    }

    func testHoveringTheExtraRowWellProposesTheCursorRow() throws {
        let model = editor()
        model.draft.cursorRow = []
        let key = try XCTUnwrap(model.draft.bottomRow.first { $0.action == .punctuation })
        model.beginDrag(key)
        let geometry = CanvasGeometry(
            keyFrames: [:],
            rowBands: [.bottom: 200...260],
            trayBand: 300...380,
            extraRowWell: 0...43,
            frozenBands: [0...43, 55...98]
        )
        model.updateDrag(at: CGPoint(x: 40, y: 20), in: geometry)
        XCTAssertEqual(model.session?.proposed, .board(row: .cursor, index: 0))
        let after = CanvasGeometry(
            keyFrames: [:],
            rowBands: [.cursor: 0...43, .bottom: 200...260],
            trayBand: 300...380,
            extraRowWell: nil,
            frozenBands: [55...98]
        )
        model.updateDrag(at: CGPoint(x: 40, y: 70), in: after)
        XCTAssertNil(model.session?.proposed)
        model.cancelDrag()
    }

    /// A hover that does not move keys must not freeze the gesture. The first
    /// tray-band update is `nil → .tray`, which draws the same layout; a later
    /// drop on the bottom row still has to resolve.
    func testATrayDragStillResolvesAfterCrossingTheTrayBand() {
        let model = editor()
        let action = model.tray.first { !$0.isRepeatable }!.action
        let id = model.beginDragFromTray(action)!
        let geometry = boardGeometry(model)
        model.updateDrag(at: CGPoint(x: 20, y: 220), in: geometry)
        XCTAssertEqual(model.session?.proposed, .tray)
        model.updateDrag(at: CGPoint(x: 20, y: 120), in: geometry)
        guard case .board(let row, _) = model.session?.proposed else {
            return XCTFail("the tray lift stayed stuck after leaving the tray")
        }
        XCTAssertEqual(row, .bottom)
        model.cancelDrag()
        XCTAssertNotNil(id)
    }

    func testPlacingFromTheTrayThenUndoingRestoresTheStart() {
        let model = editor()
        let start = model.draft
        let action = model.tray.first { !$0.isRepeatable }!.action
        let id = model.beginDragFromTray(action)!
        model.updateDrag(at: CGPoint(x: 20, y: 120), in: boardGeometry(model))
        model.endDrag(for: id)
        XCTAssertTrue(model.draft.bottomRow.contains { $0.action == action })
        model.undo()
        XCTAssertEqual(model.draft, start)
        XCTAssertFalse(model.canUndo)
    }

    func testAccessibilityActionsOmitRemoveForRequiredKeys() {
        let model = editor()
        for action: SlotAction in [.space, .ret, .numbersPlane] {
            let slot = model.draft.bottomRow.first { $0.action == action }!
            XCTAssertFalse(
                model.accessibilityActions(for: slot).contains(.remove),
                "\(action.title) offered to remove itself")
            XCTAssertFalse(model.canRemove(slot).isAllowed)
        }
        let punctuation = model.draft.bottomRow.first { $0.action == .punctuation }!
        XCTAssertTrue(model.accessibilityActions(for: punctuation).contains(.remove))
    }

    func testAnInFlightUniqueTrayItemStaysInTheTray() {
        let model = editor()
        let action = model.tray.first { !$0.isRepeatable }!.action
        let id = model.beginDragFromTray(action)!
        XCTAssertTrue(
            model.tray.contains { $0.action == action },
            "removing the chip tears down the drag gesture")
        model.cancelDrag()
        XCTAssertTrue(model.tray.contains { $0.action == action })
        XCTAssertNotNil(id)
    }

    func testTheSpaceBarCanBeReorderedOnItsRow() {
        let model = editor()
        let space = model.draft.bottomRow.first { $0.action == .space }!
        model.beginDrag(space)
        model.updateDrag(at: CGPoint(x: 20, y: 120), in: boardGeometry(model))
        XCTAssertEqual(
            model.session?.proposed,
            .board(row: .bottom, index: 0),
            "the space bar was refused a drop on its own row")
        model.cancelDrag()
    }

    func testApplyingAPresetAbandonsAnOpenDrag() {
        let model = editor()
        let key = model.draft.bottomRow.first { $0.action == .punctuation }!
        model.beginDrag(key)
        model.apply(preset: LayoutPreset.named("compact")!)
        XCTAssertNil(model.session)
        XCTAssertEqual(model.draft, LayoutPreset.named("compact")!.customization)
        XCTAssertTrue(model.canUndo)
    }

    func testWidthSnapsToHalfUnitsThenFill() {
        XCTAssertEqual(SlotWidth.snapped(from: 1.24), .units(1))
        XCTAssertEqual(SlotWidth.snapped(from: 1.26), .units(1.5))
        XCTAssertEqual(SlotWidth.snapped(from: 3.0), .units(3))
        XCTAssertEqual(SlotWidth.snapped(from: 3.4), .fill)
        XCTAssertEqual(
            SlotWidth.proposed(
                start: .units(1), startPixels: 40, translation: 40, unit: 40),
            .units(2))
    }

    func testUpdateResizePublishesTheSelectionWidth() throws {
        let model = editor()
        let key = try XCTUnwrap(model.draft.bottomRow.first { $0.action == .punctuation })
        model.selection = key
        model.beginResize(key)
        model.updateResize(.units(2))
        XCTAssertEqual(model.selection?.width, .units(2))
        model.cancelResize()
        XCTAssertEqual(model.selection?.width, key.width)
    }

    func testEditingMidResizeDoesNotLeaveTheSessionStuck() throws {
        let model = editor()
        let key = try XCTUnwrap(model.draft.bottomRow.first { $0.action == .punctuation })
        model.beginResize(key)
        model.updateResize(.units(2))
        model.setWidth(.fill, for: key)
        XCTAssertNil(model.resize)
        XCTAssertEqual(model.draft.bottomRow.first { $0.id == key.id }?.width, .fill)
    }

    func testAHandleDragIsOneUndo() throws {
        let model = editor()
        let key = try XCTUnwrap(model.draft.bottomRow.first { $0.action == .punctuation })
        let start = model.draft
        model.beginResize(key)
        model.updateResize(.units(2))
        XCTAssertEqual(model.draft, start)
        XCTAssertEqual(model.displayed.bottomRow.first { $0.id == key.id }?.width, .units(2))
        model.endResize(for: key.id)
        XCTAssertEqual(model.draft.bottomRow.first { $0.id == key.id }?.width, .units(2))
        model.undo()
        XCTAssertEqual(model.draft, start)
        XCTAssertFalse(model.canUndo)
    }

    func testTheSpaceBarCannotBeResized() throws {
        let model = editor()
        let space = try XCTUnwrap(model.draft.bottomRow.first { $0.action == .space })
        XCTAssertFalse(model.canResize(space))
        model.beginResize(space)
        XCTAssertNil(model.resize)
    }

    func testALateEndResizeFromAnotherKeyDoesNotCommit() throws {
        let model = editor()
        let key = try XCTUnwrap(model.draft.bottomRow.first { $0.action == .punctuation })
        let other = try XCTUnwrap(model.draft.bottomRow.first { $0.action == .emoji })
        let start = model.draft
        model.beginResize(key)
        model.updateResize(.units(2.5))
        model.endResize(for: other.id)
        XCTAssertEqual(model.draft, start)
        XCTAssertNotNil(model.resize)
        model.cancelResize()
        XCTAssertEqual(model.displayed, start)
    }

    func testALateEndDragFromAnotherKeyDoesNotCommit() throws {
        let model = editor()
        // `XCTUnwrap`, not `!`: a nil force-unwrap in a test kills the whole
        // runner rather than failing one case, which is how the last change to
        // the shipped bottom row took eleven tests down with it.
        let key = try XCTUnwrap(model.draft.bottomRow.first { $0.action == .punctuation })
        let other = try XCTUnwrap(model.draft.bottomRow.first { $0.action == .emoji })
        let start = model.draft
        model.beginDrag(key)
        model.updateDrag(at: CGPoint(x: 20, y: 120), in: boardGeometry(model))
        model.endDrag(for: other.id)
        XCTAssertEqual(model.draft, start)
        XCTAssertNotNil(model.session)
        model.cancelDrag()
        XCTAssertFalse(model.canUndo)
    }

    func boardGeometry(_ model: LayoutEditorModel) -> CanvasGeometry {
        var frames: [UUID: CGRect] = [:]
        for (index, slot) in model.displayed.bottomRow.enumerated() {
            frames[slot.id] = CGRect(x: CGFloat(index) * 44, y: 100, width: 40, height: 40)
        }
        for (index, slot) in model.displayed.cursorRow.enumerated() {
            frames[slot.id] = CGRect(x: CGFloat(index) * 44, y: 40, width: 40, height: 40)
        }
        var bands: [LayoutEditorModel.RowKind: ClosedRange<CGFloat>] = [
            .bottom: 94...146
        ]
        if !model.displayed.cursorRow.isEmpty {
            bands[.cursor] = 20...60
        }
        return CanvasGeometry(
            keyFrames: frames,
            rowBands: bands,
            trayBand: 200...280,
            extraRowWell: model.displayed.cursorRow.isEmpty ? 0...30 : nil
        )
    }
}
