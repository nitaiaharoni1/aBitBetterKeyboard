import UIKit
import XCTest

@testable import AIKeyboardCore

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

    var after = ""

    var documentContextBeforeInput: String? { "" }
    var documentContextAfterInput: String? { after }
    var selectedText: String? { nil }
    var isSecureTextEntry: Bool? { false }
    var textContentType: UITextContentType?? { .some(.none) }
    var keyboardType: UIKeyboardType? { .default }

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

    private func cursorController(
        before: String, selecting: String? = nil, after: String = ""
    ) -> (KeyboardController, CursorTextTarget) {
        let target = CursorTextTarget(before: before, selecting: selecting, after: after)
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

    func testForwardDeleteRemovesTheCharacterInFront() {
        let (controller, target) = cursorController(before: "hello", after: "world")
        controller.press(.deleteForward)
        XCTAssertEqual(target.document, "helloorld")
    }

    func testForwardDeleteAtEndDoesNothing() {
        // Naive move-then-delete with empty after-context erases the previous character.
        let (controller, target) = cursorController(before: "hello")
        controller.press(.deleteForward)
        XCTAssertEqual(target.document, "hello")
    }

    func testForwardDeleteRemovesASelection() {
        let (controller, target) = cursorController(before: "he", selecting: "ll", after: "o")
        controller.press(.deleteForward)
        XCTAssertEqual(target.document, "heo")
    }

    func testForwardDeleteRemovesAWholeEmoji() {
        let (controller, target) = cursorController(before: "a", after: "😀b")
        controller.press(.deleteForward)
        XCTAssertEqual(target.document, "ab")
    }

    /// `CursorTextTarget` snaps an in-cluster offset forward, so `ab` still
    /// passes against `adjustTextPosition(1)`. The offset is what rejects it.
    func testForwardDeleteMovesByTheGraphemesUTF16Count() {
        let (controller, target) = controller()
        target.after = "😀b"
        controller.press(.deleteForward)
        XCTAssertEqual(target.offsets, ["😀".utf16.count])
    }

    func testForwardDeleteTypesNothing() {
        let (controller, target) = controller()
        controller.press(.deleteForward)
        XCTAssertEqual(target.inserted, [])
    }

    func testEmojiKeyTogglesTheEmojiPanel() {
        let (controller, _) = controller()
        controller.press(.emoji)
        XCTAssertEqual(controller.overlay, .emoji)
        controller.press(.emoji)
        XCTAssertEqual(controller.overlay, .none)
    }

    func testCopyclipKeyTogglesThePanel() {
        let before = SharedStore.shared.copyclipRecord
        defer { SharedStore.shared.copyclipRecord = before }
        let (controller, _) = controller()
        controller.press(.copyclip)
        XCTAssertEqual(controller.overlay, .copyclip)
        controller.press(.copyclip)
        XCTAssertEqual(controller.overlay, .none)
    }

    /// On an empty field the one-tap key says why rather than running a rewrite,
    /// which is the same three-way answer the bar's button gives. The two must not
    /// diverge; that drift has already shipped once between the bar and the panel
    /// behind it.
    ///
    /// **This used to assert the key opened `AIMenuPanel`.** There is no menu to
    /// open, and the `.aiMenu` cap that toggled one is deleted with it — its test
    /// went too, because a key that no longer exists has no behaviour to pin. What is
    /// left is the half that always mattered: a tap on an empty field is answered.
    /// The overlay assertion is what rejects the old build, which set the same block
    /// nowhere and covered the keys instead.
    func testTheQuickToneKeySaysWhyWithNothingToRewrite() {
        let (controller, _) = controller()
        XCTAssertFalse(controller.hasTextToWorkWith)
        controller.press(.quickTone)
        XCTAssertEqual(controller.overlay, .none, "the keys must stay visible")
        XCTAssertEqual(controller.block?.action, .rewrite)
        XCTAssertEqual(controller.block?.remedy, .none, "there is no button that would help")
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

    func testSettingsKeyOpensTheContainingAppsSettingsTab() {
        let (controller, target) = controller()
        var openedURL: URL?
        controller.onOpenContainingApp = { openedURL = $0 }

        controller.press(.settings)

        XCTAssertEqual(openedURL, SharedStore.settingsURL)
        XCTAssertEqual(target.inserted, [], "the settings key must not type anything")
    }

    // MARK: Applying a layout

    func testAControllerDoesNotInventAnIOSGlobeBeforeItsHostAnswers() {
        let controller = KeyboardController(target: RecordingTextTarget(), language: .english)
        XCTAssertFalse(controller.customization.bottomRow.contains { $0.action == .globe })
        XCTAssertTrue(controller.customization.cursorRow.contains { $0.action == .settings })
    }

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

    /// The editor canvas is a preview. Inventing a globe there draws a key the
    /// model does not own, so drops land one slot to the right of the finger.
    func testAPreviewApplyDoesNotInventAGlobe() {
        let (controller, _) = controller()
        var without = KeyboardCustomization.default
        without.bottomRow.removeAll { $0.action == .globe }
        controller.apply(without, allowingIncomplete: true)
        XCTAssertFalse(
            controller.customization.bottomRow.contains { $0.action == .globe },
            "a preview apply inserted a globe the editor does not own")
    }

    /// **`showsGlobeKey = false`, because no preset carries a globe any more.**
    /// With it left true, `apply` correctly inserts one and this test fails for the
    /// repair rather than for the thing it is about, which is that a layout needing
    /// no repair is not otherwise touched. The two tests above are where the
    /// insertion itself is asserted, in both directions.
    func testAUsableLayoutIsAppliedUnchanged() {
        let (controller, _) = controller()
        controller.showsGlobeKey = false
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
