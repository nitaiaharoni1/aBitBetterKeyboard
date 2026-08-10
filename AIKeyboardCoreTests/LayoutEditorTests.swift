import UIKit
import XCTest

@testable import AIKeyboardCore

// MARK: - The editor's arithmetic

@MainActor
final class LayoutEditorTests: XCTestCase {

    private func editor(_ layout: KeyboardCustomization = .default) -> LayoutEditorModel {
        LayoutEditorModel(layout: layout, showsGlobe: true)
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
        model.setExtraRow(enabled: true)
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

    func testRemovingTheGlobeIsRefused() {
        let model = editor()
        let globe = model.draft.bottomRow.first { $0.action == .globe }!
        model.remove(globe)
        XCTAssertTrue(model.draft.bottomRow.contains(globe))
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

    /// Switching the extra row off and on gives back what the row ships holding,
    /// not something else. It seeded arrows-and-hide while the row was the cursor
    /// row; once it became the action row that seed was silently wrong.
    func testTurningTheExtraRowOnSeedsItWithTheShippedActionRow() {
        let model = editor()
        model.setExtraRow(enabled: false)
        XCTAssertTrue(model.draft.cursorRow.isEmpty)
        model.setExtraRow(enabled: true)
        XCTAssertEqual(
            model.draft.cursorRow.map(\.action),
            KeyboardCustomization.actionRow.map(\.action))
    }

    func testTheExtraRowIsListedOnlyWhenItExists() {
        let model = editor()
        // The default ships the row populated, so switch it off first: an empty
        // `cursorRow` is what "the row is off" means.
        model.setExtraRow(enabled: false)
        XCTAssertFalse(model.visibleRows.contains(.cursor))
        model.setExtraRow(enabled: true)
        XCTAssertTrue(model.visibleRows.contains(.cursor))
    }

    func testRowKindFindsAKeyInEveryRow() {
        let model = editor()
        model.setExtraRow(enabled: true)
        // **The bar ends are empty in the shipped default now** — the emoji key,
        // the one-tap rewrite and the sparkle all moved into the action row — so
        // this has to put something in them rather than index into them. It used
        // to index straight in and crashed the whole runner when the default
        // changed, which took 367 later tests with it and reported as
        // `** TEST FAILED **` with no failing assertion anywhere.
        model.add(.emoji, to: .barLeading)
        model.add(.aiMenu, to: .barTrailing)
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
}

// MARK: - Persistence

/// Drives the decode path against a scratch suite. The singleton's own defaults
/// are the App Group plist and are nobody's fixture.
final class LayoutStoreTests: XCTestCase {

    private var defaults: UserDefaults!
    private let suite = "LayoutStoreTests"

    override func setUp() {
        super.setUp()
        UserDefaults().removePersistentDomain(forName: suite)
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testAnAbsentKeyIsTheShippedDefault() {
        XCTAssertEqual(SharedStore.decodeLayout(from: defaults), .default)
    }

    func testGarbageDecodesToTheDefaultRatherThanCrashing() {
        defaults.set(Data("not json".utf8), forKey: SharedStore.layoutKey)
        XCTAssertEqual(SharedStore.decodeLayout(from: defaults), .default)
    }

    /// A build that adds a new required key must not brick a keyboard saved by the
    /// build before it. The user cannot fix a keyboard that will not draw from
    /// inside the keyboard.
    func testAnInvalidStoredLayoutFallsBackToTheDefault() throws {
        var broken = KeyboardCustomization.default
        broken.bottomRow.removeAll { $0.action == .space }
        defaults.set(try JSONEncoder().encode(broken), forKey: SharedStore.layoutKey)
        XCTAssertEqual(SharedStore.decodeLayout(from: defaults), .default)
    }

    func testAValidStoredLayoutComesBack() throws {
        let roomy = LayoutPreset.named("roomy")!.customization
        defaults.set(try JSONEncoder().encode(roomy), forKey: SharedStore.layoutKey)
        XCTAssertEqual(SharedStore.decodeLayout(from: defaults), roomy)
    }

    /// **A layout missing the globe decodes fine, and that is deliberate.**
    /// Whether the key is required belongs to the device, not to the store, so the
    /// store validates with `showsGlobe: false` and
    /// `KeyboardController.apply(_:)` puts it back where the answer is known.
    func testAGlobelessLayoutSurvivesTheStore() throws {
        var without = KeyboardCustomization.default
        without.bottomRow.removeAll { $0.action == .globe }
        defaults.set(try JSONEncoder().encode(without), forKey: SharedStore.layoutKey)
        XCTAssertEqual(SharedStore.decodeLayout(from: defaults), without)
    }

    /// **The keyboard is a second process.** `load()` fills the published copy
    /// once per launch, so a keyboard already on screen when the user taps Done
    /// has to read through `UserDefaults` again. The broken version returns the
    /// launch-time copy, so this writes *after* the read that would have cached
    /// it.
    func testTheStoredAccessorSeesAWriteMadeAfterItWasFirstRead() throws {
        XCTAssertEqual(SharedStore.decodeLayout(from: defaults), .default)
        let power = LayoutPreset.named("power")!.customization
        defaults.set(try JSONEncoder().encode(power), forKey: SharedStore.layoutKey)
        XCTAssertEqual(SharedStore.decodeLayout(from: defaults), power)
    }
}

// MARK: - What the new keys actually do

/// A target that records the calls made against it.
///
/// `MockTextTarget.adjustTextPosition` is a deliberate no-op — it has no cursor
/// to move — so it cannot answer whether a cursor key moved anything.
@MainActor
final class RecordingTextTarget: TextTarget {
    var offsets: [Int] = []
    var inserted: [String] = []
    var deletions = 0

    var documentContextBeforeInput: String? { "" }
    var documentContextAfterInput: String? { "" }
    var selectedText: String? { nil }
    var isSecureTextEntry: Bool? { false }
    var textContentType: UITextContentType?? { .some(.none) }

    func insertText(_ text: String) { inserted.append(text) }
    func deleteBackward() { deletions += 1 }
    func adjustTextPosition(byCharacterOffset offset: Int) { offsets.append(offset) }
}

@MainActor
final class CustomKeyActionTests: XCTestCase {

    private func controller() -> (KeyboardController, RecordingTextTarget) {
        let target = RecordingTextTarget()
        let controller = KeyboardController(target: target, language: .english)
        controller.showsGlobeKey = true
        controller.apply(.default)
        return (controller, target)
    }

    func testCursorKeysMoveTheInsertionPointAndTypeNothing() {
        let (controller, target) = controller()
        controller.press(.cursorLeft)
        controller.press(.cursorRight)
        XCTAssertEqual(target.offsets, [-1, 1])
        XCTAssertEqual(target.inserted, [], "a cursor key must not type anything")
        XCTAssertEqual(target.deletions, 0)
    }

    func testEmojiKeyTogglesTheEmojiPanel() {
        let (controller, _) = controller()
        controller.press(.emoji)
        XCTAssertEqual(controller.overlay, .emoji)
        controller.press(.emoji)
        XCTAssertEqual(controller.overlay, .none)
    }

    func testAIMenuKeyTogglesTheMenu() {
        let (controller, _) = controller()
        controller.press(.aiMenu)
        XCTAssertEqual(controller.overlay, .aiMenu)
        controller.press(.aiMenu)
        XCTAssertEqual(controller.overlay, .none)
    }

    /// On an empty field the one-tap key opens the menu instead of running a
    /// rewrite, which is the same three-way answer the bar's button gives. The two
    /// must not diverge; that drift has already shipped once between the bar and
    /// the panel behind it.
    func testTheQuickToneKeyOpensTheMenuWithNothingToRewrite() {
        let (controller, _) = controller()
        XCTAssertFalse(controller.hasTextToWorkWith)
        controller.press(.quickTone)
        XCTAssertEqual(controller.overlay, .aiMenu)
    }

    /// Nothing in the package can dismiss a keyboard, so the cap has to reach the
    /// host through a callback the way the globe key already does.
    func testHideKeyboardCallsTheHost() {
        let (controller, _) = controller()
        var dismissed = 0
        controller.onDismissKeyboard = { dismissed += 1 }
        controller.press(.hideKeyboard)
        XCTAssertEqual(dismissed, 1)
    }

    func testHideKeyboardWithNoHostDoesNothing() {
        let (controller, target) = controller()
        controller.press(.hideKeyboard)
        XCTAssertEqual(target.inserted, [])
    }

    // MARK: Applying a layout

    /// The device decides whether the globe is drawn, and the stored layout does
    /// not know. A layout saved on a phone with one keyboard installed must not
    /// strand the user the day they install a second.
    func testTheControllerPutsTheGlobeBackWhenTheSystemNeedsIt() {
        let (controller, _) = controller()
        var without = KeyboardCustomization.default
        without.bottomRow.removeAll { $0.action == .globe }
        controller.apply(without)
        XCTAssertTrue(controller.customization.bottomRow.contains { $0.action == .globe })
    }

    func testTheControllerLeavesTheGlobeOutWhenTheSystemDoesNotNeedIt() {
        let (controller, _) = controller()
        controller.showsGlobeKey = false
        var without = KeyboardCustomization.default
        without.bottomRow.removeAll { $0.action == .globe }
        controller.apply(without)
        XCTAssertFalse(controller.customization.bottomRow.contains { $0.action == .globe })
    }

    func testAUsableLayoutIsAppliedUnchanged() {
        let (controller, _) = controller()
        let roomy = LayoutPreset.named("roomy")!.customization
        controller.apply(roomy)
        XCTAssertEqual(controller.customization, roomy)
    }

    /// A layout the repair cannot save falls all the way back, because a keyboard
    /// that will not draw is not a state the user can escape from inside it.
    func testAnUnusableLayoutFallsBackToTheDefault() {
        let (controller, _) = controller()
        var broken = KeyboardCustomization.default
        broken.bottomRow.removeAll { $0.action == .ret }
        controller.apply(broken)
        XCTAssertEqual(controller.customization, .default)
    }
}
