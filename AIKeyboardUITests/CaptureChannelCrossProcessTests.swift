import XCTest

/// Drives the capture channel across two real processes.
///
/// The app runs `CaptureChannelProbe`, which is the *real* `CaptureChannelWriter`
/// and the *real* `FrameFingerprint` over synthetic frames; iOS launches the
/// keyboard extension in its own sandbox, where `ScreenContextChannel` maps the
/// same pages and applies the same freshness gate. Neither side is a stub and
/// neither side can see the other's memory.
///
///     Scripts/prove-capture-channel.sh
///
/// **The verdict is not in this file.** What this test does is get both
/// processes running and hold them there long enough for the timeline to play
/// out; what proves the channel works is the keyboard extension's own log lines,
/// which the OS stamps with the process that emitted them and which the script
/// reads. That is the same division `AppGroupCrossProcessTests` uses and for the
/// same reason: reading another process's accessibility hierarchy is what makes
/// these tests flaky, while a log line stamped by the kernel cannot be faked by
/// the app.
///
/// What this test asserts on its own is only that the extension ran at all,
/// because a script that greps for lines from a process that never started
/// would otherwise report "no evidence" as "no problem".
final class CaptureChannelCrossProcessTests: KeyboardExtensionTestCase {

    /// Long enough for the probe's whole timeline: the keyboard is seen, a
    /// reading is published for the screen on show, and five seconds later the
    /// conversation changes underneath it.
    private let observationWindow: TimeInterval = 14

    override var extraLaunchArguments: [String] { ["-uiTestCaptureChannel"] }

    func testKeyboardExtensionReadsTheCaptureChannelWrittenByAnotherProcess() throws {
        app.launch()
        skipOnboardingIfPresent()
        app.terminate()

        // Full Access is not optional here: without it iOS keeps the App Group
        // container from the keyboard entirely, so there is no channel to read
        // and the run would prove nothing rather than fail.
        try enableKeyboardWithFullAccess()

        app.launch()
        skipOnboardingIfPresent()
        openPersonalDictionaryAndFocusTextField()
        try switchToAIKeyboard()

        let keyboardIsUp =
            app.descendants(matching: .any).matching(identifier: englishOnlyKey).firstMatch
            .waitForExistence(timeout: 10)
            || app.descendants(matching: .any).matching(identifier: hebrewOnlyKey).firstMatch.exists
        XCTAssertTrue(
            keyboardIsUp,
            "The keyboard extension never appeared, so nothing was proved either way.")

        // Both processes are now live. Hold them there while the probe publishes
        // screen A, the keyboard confirms a reading of it, and the probe switches
        // to screen B.
        Thread.sleep(forTimeInterval: observationWindow)
    }
}
