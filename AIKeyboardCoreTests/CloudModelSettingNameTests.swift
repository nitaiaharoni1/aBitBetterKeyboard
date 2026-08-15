import XCTest

@testable import AIKeyboardCore
@testable import AIKeyboardShared

/// One recovery sentence, used wherever an unconnected app dead-ends, and the
/// rule that it must not describe the plumbing.
///
/// `cloudBackendURL` is read by three processes. Before attestation, failures
/// pointed at a field titled "Where the screen is read" or said nothing useful.
/// Then they pointed at a real screen, which was an improvement until the screen
/// stopped having anything on it a user could act on: `AppAttestation` fills the
/// bearer, at launch, on foreground and on a background refresh, so the only
/// honest thing to report is that it is reconnecting.
///
/// These assert both halves of that: every dead end names the same recovery, and
/// none of them says "cloud model" to somebody who has never been shown one.
final class CloudModelSettingNameTests: XCTestCase {

    /// Every message a user can reach when the app has not connected.
    private var deadEnds: [(String, String)] {
        [
            ("unsupportedLanguage", AIEngineError.unsupportedLanguage(.hebrew).message),
            ("cloudNotConfigured", AIEngineError.cloudNotConfigured.message),
            ("deviceNotSupported", AIEngineError.deviceNotSupported.message),
            ("notConfigured", ScreenContextEndReason.notConfigured.recovery)
        ]
    }

    /// The four failures that dead-end on the cloud all say the same next step.
    func testEveryDeadEndNamesTheSameRecovery() {
        for (name, message) in deadEnds {
            XCTAssertTrue(
                message.contains(BackendTransport.setUpRecovery),
                "\(name) reports an unconnected app and names no recovery: \(message)")
        }
    }

    /// **The words "cloud model" are ours, not the user's.**
    ///
    /// Nothing in the shipping app offers a cloud model, asks for one, or lets
    /// anybody change one — the row that reached that screen is compiled out of
    /// Release. A failure that names it tells the owner of a keyboard that a
    /// component they have never heard of is broken and implies they were meant
    /// to have configured it.
    ///
    /// Asserted over the rendered strings rather than by reading the source,
    /// because the leak that prompted this was an interpolation: the sentence
    /// naming the component lived in `setUpRecovery` and arrived inside four
    /// messages that each looked clean where they were written.
    func testNoDeadEndNamesTheCloudModelAtTheUser() {
        let titles = [
            ("cloudNotConfigured", AIEngineError.cloudNotConfigured.title),
            ("notConfigured", ScreenContextEndReason.notConfigured.explanation)
        ]
        for (name, text) in deadEnds + titles {
            XCTAssertFalse(
                text.localizedCaseInsensitiveContains("cloud model"),
                "\(name) says 'cloud model' to somebody who has never been shown one: \(text)")
        }
    }

    /// **The recovery is a status, not an errand.** "Open aBitBetterKeyboard once to
    /// reconnect" was an instruction, and the keyboard cannot carry it out on the
    /// user's behalf: an extension has no `UIApplication`. The app reconnects on
    /// its own at launch, on foreground and on a background wake-up, so the
    /// sentence reports that instead of assigning it.
    ///
    /// `settingsPath` is leftover. Nothing may send a person there.
    func testTheRecoveryReportsRatherThanInstructs() {
        XCTAssertFalse(
            BackendTransport.setUpRecovery.contains(BackendTransport.settingsPath),
            "recovery still points at a settings row that does not exist")
        XCTAssertEqual(
            BackendTransport.setUpRecovery, "aBitBetterKeyboard is reconnecting. Try again in a moment.")
        XCTAssertFalse(
            BackendTransport.setUpRecovery.localizedCaseInsensitiveContains("open ai keyboard"),
            "the recovery tells the user to open an app they are often already in")
    }

    /// The screen-context ending says what is true of the app rather than
    /// blaming screen reading for something four other features share.
    ///
    /// **The name is `aBitBetterKeyboard`, and this test asserted the old one.**
    /// It read `"ai keyboard"`, which is the Xcode target, the folder and the
    /// bundle id, and has not been the name a user sees since the rename. The
    /// string it checks has said `aBitBetterKeyboard` since then, so this has
    /// been failing on committed main while reporting the opposite of what was
    /// wrong. The product name is spelled out in nineteen places with no shared
    /// constant, which is how one of them was missed; the sibling assertion
    /// above already uses the new name.
    func testTheScreenContextRefusalNamesTheApp() {
        let explanation = ScreenContextEndReason.notConfigured.explanation
        XCTAssertTrue(
            explanation.localizedCaseInsensitiveContains("aBitBetterKeyboard"),
            "the ending blames screen reading for a state the whole app is in: \(explanation)")
        XCTAssertFalse(
            explanation.localizedCaseInsensitiveContains("in this build"),
            "it reconnects on its own, so it is not something the build withheld")
    }
}
