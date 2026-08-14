import ReplayKit
import UIKit
import XCTest

@testable import AIKeyboardCore

/// The overlay stretch is load-bearing for the app's `BroadcastPickerButton`:
/// `RPSystemBroadcastPickerView` cannot be pressed from SwiftUI, so the system
/// `UIButton` has to fill the host bounds. Asserting "a picker is offered"
/// would pass against a 10-pt-smaller chip.
///
/// Reply with no session hosts ReplayKit on the key and on the sentence
/// (`.broadcastPicker`). `.openApp` remains for dictation.
final class BroadcastPickerBannerTests: XCTestCase {

    private let noSession = BannerState.Block(
        action: .reply,
        title: "Screen context is off",
        detail: "Tap to pick aBitBetterKeyboard, then Start Broadcast.",
        remedy: .broadcastPicker)

    private let needsAccess = BannerState.Block(
        action: .reply,
        title: "Needs Full Access",
        detail: "Turn on Full Access.",
        remedy: .none)

    private let broadcastPicker = BannerState.Block(
        action: .reply,
        title: "Screen context is off",
        detail: "Tap to pick aBitBetterKeyboard, then Start Broadcast.",
        remedy: .broadcastPicker)

    /// Reply with no session hosts ReplayKit on the sentence. Trailing is ×.
    /// Dictation still uses × plus the Open chip.
    func testABroadcastRefusalDismissesWithXRatherThanTheRecordChip() {
        XCTAssertEqual(ActionBanner.blockedTrailing(for: noSession.remedy), .dismiss)
        XCTAssertTrue(
            noSession.startsBroadcastFromMessage,
            "the no-session sentence is inert; only a chip would start a broadcast")

        XCTAssertEqual(ActionBanner.blockedTrailing(for: needsAccess.remedy), .dismiss)
        XCTAssertFalse(
            needsAccess.startsBroadcastFromMessage,
            "a refusal that must not start a recording still hosts the picker")

        XCTAssertEqual(
            ActionBanner.blockedTrailing(for: broadcastPicker.remedy),
            .dismiss,
            "the record-dot chip is still the trailing control")
        XCTAssertTrue(
            broadcastPicker.startsBroadcastFromMessage,
            "the sentence is still inert; only the chip started a broadcast")

        let openApp = BannerState.Block(
            action: nil,
            title: "Open the app",
            detail: "Dictation runs there.",
            remedy: .openApp(URL(string: "aikeyboard://dictate")!))
        guard case .dismissAndOpenApp = ActionBanner.blockedTrailing(for: openApp.remedy)
        else { return XCTFail("the open-app chip was dropped") }
        XCTAssertFalse(openApp.startsBroadcastFromMessage)
    }

    /// `-[RPSystemBroadcastPickerView addBroadcastPickerButton]` insets its
    /// `UIButton` 5pt on every edge. An overlay that does not stretch that
    /// button leaves a 10-pt-smaller target floating over the sentence, which
    /// is the chip we just removed, just invisible. The broken build is a
    /// picker whose button is smaller than its own bounds.
    @MainActor
    func testTheOverlayStretchesTheSystemButtonAcrossTheMessage() throws {
        let picker = BroadcastPickerOverlayView(
            frame: CGRect(x: 0, y: 0, width: 280, height: 60))
        picker.hidesSystemGlyph = true
        picker.layoutIfNeeded()

        let button = try XCTUnwrap(
            picker.subviews.compactMap { $0 as? UIButton }.first,
            "ReplayKit no longer vends a UIButton; the overlay has nothing to press")
        XCTAssertEqual(
            button.frame, picker.bounds,
            "the system button is still inset (\(button.frame) in \(picker.bounds)); a tap on the sentence misses it"
        )
        XCTAssertTrue(
            button.subviews.allSatisfy(\.isHidden),
            "the record glyph is still drawn over the sentence")

        let installed: ([String]) -> [String] = { actions in
            actions.filter { $0.contains("handleBroadcastActivation") }
        }
        XCTAssertEqual(
            installed(button.actions(forTarget: picker, forControlEvent: .touchUpInside) ?? [])
                .count,
            0,
            "the banner overlay still installs a no-op target")

        picker.onActivation = {}
        picker.layoutIfNeeded()
        XCTAssertEqual(
            button.frame, picker.bounds,
            "adding the activation target inset the button (\(button.frame) in \(picker.bounds))")
        picker.layoutIfNeeded()
        let after = installed(
            button.actions(forTarget: picker, forControlEvent: .touchUpInside) ?? [])
        XCTAssertEqual(
            after.count, 1,
            "layoutSubviews stacked extra activation targets: \(after)")
    }
}
