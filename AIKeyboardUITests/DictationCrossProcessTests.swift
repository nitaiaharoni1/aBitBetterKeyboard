import XCTest

/// Drives the dictation channel across two real processes.
///
/// The app runs `DictationChannelProbe`, which is the *real*
/// `DictationChannelWriter` with the microphone and the transcriber replaced by
/// a fixed sentence; iOS launches the keyboard extension in its own sandbox,
/// where `DictationSession` maps the same pages. Neither side can see the
/// other's memory.
///
///     Scripts/prove-dictation.sh
///
/// **The verdict is not in this file**, for the reason
/// `CaptureChannelCrossProcessTests` gives: reading another process's
/// accessibility hierarchy is what makes these tests flaky, while a log line the
/// OS stamps with the emitting process cannot be faked by the app. What this
/// asserts on its own is only that the extension ran at all, so a script that
/// greps for lines from a process that never started cannot report "no evidence"
/// as "no problem".
final class DictationCrossProcessTests: KeyboardExtensionTestCase {

    /// Long enough for the keyboard to find the session, open an utterance, and
    /// receive the transcript the other process publishes.
    private let observationWindow: TimeInterval = 10

    override var extraLaunchArguments: [String] { ["-uiTestDictationChannel"] }

    func testKeyboardExtensionDictatesThroughASessionInAnotherProcess() throws {
        app.launch()
        skipOnboardingIfPresent()
        app.terminate()

        // Full Access is not optional: without it iOS keeps the App Group
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

        // Open the dictation panel from the keyboard's own microphone key, so
        // the utterance is opened by the extension process rather than by
        // anything in this test.
        let microphone = app.descendants(matching: .any).matching(identifier: "key-dictation")
            .firstMatch
        if microphone.waitForExistence(timeout: 5) {
            microphone.tap()

            // Long enough for the recorder to publish a partial — it sends one half
            // a second in — and for the keyboard's 10 Hz poll to notice it. That is
            // what `Scripts/prove-dictation.sh`'s `partial=` check reads back.
            Thread.sleep(forTimeInterval: 2)

            // **The second tap is the stop, and this used to wait on a button that
            // no longer exists.** Finishing a recording was `dictation-insert` in a
            // panel over the keys; the panel is deleted and the identifier went with
            // it, so this spent five seconds waiting for an element nothing draws
            // and then never stopped the utterance at all. The recorder therefore
            // never published a transcript, and check 4's transcript assertion —
            // the one the whole script is for — could not pass on any build. The
            // microphone key both starts and finishes now; see
            // `KeyboardController.toggleDictation`.
            microphone.tap()
        }

        Thread.sleep(forTimeInterval: observationWindow)
    }
}
