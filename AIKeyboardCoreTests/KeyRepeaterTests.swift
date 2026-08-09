import XCTest

@testable import AIKeyboardCore

/// The loop behind a held delete key.
///
/// **What it used to be, and why that was a data-loss bug rather than a leak.**
/// `KeyView` started a bare `Task` on finger-down that ran
/// `while !Task.isCancelled { onRepeat(); … }` with no bound, and cancelled it in
/// exactly one place: `DragGesture.onEnded`. SwiftUI does not call `onEnded` for a
/// *cancelled* touch — a banner, a Control Centre pull, the host resigning first
/// responder — so a held backspace interrupted that way was never stopped. It was
/// harmless only because `KeyboardController.target` was `weak` and always nil on
/// a device, so the loop deleted from nothing. Making typing work turned the same
/// loop into one that deletes from whichever document is focused next, twenty-two
/// times a second, until iOS kills the extension.
///
/// Two of the three defences are observable from here and both assert something
/// the old loop did not do: it stops itself, and it dies with its owner. The
/// third — the `@GestureState` reset in `KeyView` that fires on cancellation —
/// needs a real touch sequence and so needs a UI test.
@MainActor
final class KeyRepeaterTests: XCTestCase {

    /// **The bound.** The old loop had none: `while !Task.isCancelled` and nothing
    /// else. Held to a limit of four here so the whole life of the loop fits in a
    /// few milliseconds; in the shipping configuration the same rule stops it
    /// after about two hundred characters.
    ///
    /// `withExtendedLifetime` is load-bearing. Without it ARC may release the
    /// repeater as soon as `start` returns, `deinit` cancels, the ticks stop, and
    /// the test passes for the wrong reason — while the property it claims to
    /// prove is untested.
    func testTheRepeatStopsItselfRatherThanRunningUntilSomethingElseStopsIt() async {
        let target = MockTextTarget(text: String(repeating: "a", count: 500))
        let repeater = KeyRepeater(
            initialDelay: .milliseconds(10),
            firstInterval: .milliseconds(5),
            shortestInterval: .milliseconds(5),
            acceleration: .zero,
            limit: 4)

        repeater.start { target.deleteBackward() }
        try? await Task.sleep(for: .milliseconds(300))

        withExtendedLifetime(repeater) {
            XCTAssertEqual(
                target.text.count, 496,
                "the repeat deleted \(500 - target.text.count) characters in 300ms against a limit of 4")
        }
    }

    /// **The owner.** `repeatTask` lived in `@State`, and discarding a view drops
    /// the storage without cancelling what is in it. A key taken off screen
    /// mid-press — a plane switch, a language switch, the keyboard being dismissed
    /// — left the loop running against the host's document with nothing on screen
    /// to explain it.
    func testDroppingTheKeyStopsTheRepeat() async {
        let target = MockTextTarget(text: String(repeating: "a", count: 5000))
        var repeater: KeyRepeater? = KeyRepeater(
            initialDelay: .milliseconds(5),
            firstInterval: .milliseconds(5),
            shortestInterval: .milliseconds(5),
            acceleration: .zero,
            limit: 100_000)

        repeater?.start { target.deleteBackward() }
        try? await Task.sleep(for: .milliseconds(80))
        XCTAssertLessThan(
            target.text.count, 5000,
            "the repeat never started, so the rest of this test proves nothing")

        repeater = nil

        // One interval of grace for a tick already in flight, then a window long
        // enough for dozens more had the task survived its owner.
        try? await Task.sleep(for: .milliseconds(50))
        let settled = target.text.count
        try? await Task.sleep(for: .milliseconds(250))

        XCTAssertEqual(
            target.text.count, settled,
            "\(settled - target.text.count) more characters were deleted after the key was gone")
    }

    /// The path that always worked, kept as a regression guard rather than as a
    /// bug pin: lifting a finger normally still stops the repeat at once.
    func testStopEndsTheRepeatAtOnce() async {
        let target = MockTextTarget(text: String(repeating: "a", count: 5000))
        let repeater = KeyRepeater(
            initialDelay: .milliseconds(5),
            firstInterval: .milliseconds(5),
            shortestInterval: .milliseconds(5),
            acceleration: .zero,
            limit: 100_000)

        repeater.start { target.deleteBackward() }
        try? await Task.sleep(for: .milliseconds(80))
        repeater.stop()

        let settled = target.text.count
        try? await Task.sleep(for: .milliseconds(250))
        withExtendedLifetime(repeater) {
            XCTAssertEqual(target.text.count, settled)
        }
    }

    /// A tap is not a repeat. The first delete comes from `KeyView`'s own
    /// finger-down handler, so the loop must produce nothing at all until the hold
    /// delay has passed — otherwise every single tap deletes twice.
    func testATapDeletesNothingThroughTheRepeat() async {
        let target = MockTextTarget(text: "abc")
        let repeater = KeyRepeater(
            initialDelay: .milliseconds(200),
            firstInterval: .milliseconds(5),
            shortestInterval: .milliseconds(5),
            acceleration: .zero,
            limit: 100_000)

        repeater.start { target.deleteBackward() }
        try? await Task.sleep(for: .milliseconds(20))
        repeater.stop()
        try? await Task.sleep(for: .milliseconds(300))

        withExtendedLifetime(repeater) {
            XCTAssertEqual(target.text, "abc")
        }
    }
}
