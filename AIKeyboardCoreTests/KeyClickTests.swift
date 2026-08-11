import XCTest

@testable import AIKeyboardCore

/// Which of iOS's three keyboard sounds each key plays.
///
/// **The build this replaces played `tock` for four keys and nothing for the rest.**
/// Backspace, shift, the plane switch, globe, the cursor keys and the whole action
/// row were silent, and a held delete — the one gesture that repeats — made a
/// single sound at the start and then ran mute for two hundred characters.
final class KeyClickTests: XCTestCase {

    /// The three IDs are `/System/Library/Audio/UISounds`' own, and a typo here is
    /// not a compile error: `1105` and `1157` both exist and both play something
    /// that is not a keyboard.
    func testTheSoundIDsAreTheOnesIOSUsesForAKeyboard() {
        XCTAssertEqual(KeyClick.tock.rawValue, 1104)
        XCTAssertEqual(KeyClick.delete.rawValue, 1155)
        XCTAssertEqual(KeyClick.modifier.rawValue, 1156)
    }

    /// The assertion that rejects the old build: it answered `tock` for everything
    /// it answered at all, so any test asking only "does backspace have a sound"
    /// would have passed against a keyboard whose delete key clicked like a letter.
    func testDeleteDoesNotSoundLikeALetter() {
        XCTAssertEqual(KeyCap.backspace.clickSound, .delete)
        XCTAssertNotEqual(KeyCap.backspace.clickSound, KeyCap.character("a").clickSound)
        XCTAssertNotEqual(KeyCap.backspace.clickSound, KeyCap.shift.clickSound)
    }

    /// Text in, `tock` out. Space and return included: the system keyboard makes no
    /// distinction and neither does this one.
    func testEveryKeyThatPutsTextInPlaysTock() {
        for cap in [KeyCap.character("a"), .character("א"), .space, .ret] {
            XCTAssertEqual(cap.clickSound, .tock, "\(cap.accessibilityLabel)")
        }
    }

    /// Everything that changes what the keyboard *is* rather than what the document
    /// says. The action-row keys are in here rather than silent because the layout
    /// editor can move any of them into the letter grid, where a mute key sitting
    /// among clicking ones reads as one that missed the tap.
    func testEveryKeyThatChangesTheKeyboardPlaysTheModifierSound() {
        let caps: [KeyCap] = [
            .shift, .plane(.numbers, label: "123"), .globe, .settings, .dictation,
            .emoji, .quickTone, .cursorLeft, .cursorRight, .hideKeyboard, .aiReply, .aiFix
        ]
        for cap in caps {
            XCTAssertEqual(cap.clickSound, .modifier, "\(cap.accessibilityLabel)")
        }
    }

    /// There is deliberately no "every cap has a sound" test here. `KeyCap` carries
    /// associated values so it cannot be `CaseIterable`, and a test walking a list
    /// spelled out by hand proves only that the list was spelled out by hand — it
    /// would keep passing for the one case it exists to catch, a cap added later.
    /// The exhaustive `switch` in `clickSound` is the real guard, and it fails at
    /// compile time rather than in a run nobody started.
}
