import XCTest

@testable import AIKeyboardCore

/// What the keyboard offers when Reply is tapped with no session behind it.
///
/// `ActionBanner` renders a title, a sentence and a dismiss × off this — it
/// was `AIResultPanel` until that panel was deleted — and the sentence is the
/// one worth pinning: when `offersPicker` is true a tap starts a **real screen
/// recording**, with iOS's own countdown and its own red indicator, and a
/// broadcast started with no cloud model behind it is refused by
/// `SampleHandler.broadcastStarted` inside a second
/// — `ScreenContextEndReason.refusalToStart(canRead:)` is the decision. So the
/// picker must not be offered in that state, and it was.
final class ScreenContextPromptTests: XCTestCase {

    private func prompt(
        channel: Bool = true, cloud: Bool = true, ended: ScreenContextEndReason? = nil
    ) -> ScreenContextPrompt {
        ScreenContextPrompt(canReachChannel: channel, cloudConfigured: cloud, ended: ended)
    }

    /// The defect. The broken version is `canReachChannel && (ended?.canRestart ??
    /// true)`, which is `true` here — a keyboard on a stock install offering to
    /// record the user's screen for a session that cannot outlive the countdown.
    func testThePickerIsWithheldWhenThereIsNoCloudModel() {
        let withoutCloud = prompt(cloud: false)
        XCTAssertFalse(
            withoutCloud.offersPicker,
            "the keyboard offers to start a broadcast that iOS ends inside a second")
        XCTAssertTrue(
            withoutCloud.detail.contains(BackendTransport.setUpRecovery),
            "and it does not say what would make it work: \(withoutCloud.detail)")
        // Names the state, not the component. See
        // `CloudModelSettingNameTests.testNoDeadEndNamesTheCloudModelAtTheUser`.
        XCTAssertEqual(withoutCloud.title, "Not connected")
        XCTAssertFalse(
            withoutCloud.detail.localizedCaseInsensitiveContains("cloud model"),
            "the prompt names a component the user has never been shown: \(withoutCloud.detail)")
    }

    /// The other half, and it is not redundant: a version that simply never
    /// offered the picker would pass the test above and leave the one entry point
    /// into this feature dead. The keyboard is the only surface that can start a
    /// session without a trip to the app.
    func testThePickerIsOfferedWhenABroadcastCouldActuallyRun() {
        let ready = prompt()
        XCTAssertTrue(ready.offersPicker)
        XCTAssertEqual(ready.title, "Screen context is off")
        XCTAssertTrue(ready.detail.contains("Start Broadcast"))
        XCTAssertTrue(
            ready.detail.hasPrefix("Tap"),
            "the sentence has to say a tap starts it, or it still reads as a dead notice: \(ready.detail)")
    }

    /// Three refusals, three different pieces of work, in three different places.
    /// Collapsing any pair would send somebody to Settings › General for a missing
    /// backend, or to a backend field for a missing permission.
    func testTheThreeRefusalsSayDifferentThings() {
        let noChannel = prompt(channel: false, cloud: false)
        let noCloud = prompt(cloud: false)
        let deadEnding = prompt(ended: .notConfigured)

        XCTAssertFalse(noChannel.offersPicker)
        XCTAssertFalse(noCloud.offersPicker)
        XCTAssertFalse(deadEnding.offersPicker)

        XCTAssertEqual(noChannel.title, "Needs Full Access")
        XCTAssertTrue(noChannel.detail.contains("Full Access"))
        // Full Access comes first, because without the App Group the keyboard
        // could not read a reading even if one existed — and it cannot see the
        // shared store to know whether a backend is set either.
        XCTAssertEqual(prompt(channel: false, cloud: true).detail, noChannel.detail)

        XCTAssertNotEqual(noCloud.detail, noChannel.detail)
        XCTAssertEqual(
            deadEnding.detail,
            "\(ScreenContextEndReason.notConfigured.explanation)\n"
                + ScreenContextEndReason.notConfigured.recovery,
            "the panel and the strip have to print one page's ending the same way")
    }

    /// An ending a restart *would* fix still offers the restart, so the guard added
    /// for the cloud has not quietly disabled the ordinary case.
    func testAnEndingARestartFixesStillOffersThePicker() {
        for reason in [ScreenContextEndReason.stopped, .lost, .noFrames, .notEnded] {
            XCTAssertTrue(
                prompt(ended: reason).offersPicker, "\(reason) is fixed by starting another one")
        }
    }
}
