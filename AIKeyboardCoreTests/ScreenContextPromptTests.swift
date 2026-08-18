import XCTest

@testable import AIKeyboardCore

/// What the keyboard offers when Reply is tapped with nothing to reply to.
///
/// `ActionBanner` renders a title, a sentence and a trailing control off this —
/// it was `AIResultPanel` until that panel was deleted — and the sentence is the
/// one worth pinning, for two different reasons on either side of
/// `FeatureFlags.screenCaptureReply`.
///
/// **With capture permitted**, `offersPicker == true` means a tap starts a
/// **real screen recording**, with iOS's own countdown and its own red
/// indicator, and a broadcast started with no backend behind it is refused by
/// `SampleHandler.broadcastStarted` inside a second —
/// `ScreenContextEndReason.refusalToStart(canRead:)` is the decision. So the
/// start must not be offered in that state, and it was.
///
/// **With capture off, which is every shipping build**, the same type must not
/// name screen context at all: there is no broadcast to start and no ending a
/// restart could fix, so the sentences are the clipboard's and `offersPicker` is
/// false everywhere. The flag is passed in rather than read from
/// `FeatureFlags` so both halves stay testable while only one of them ships.
final class ScreenContextPromptTests: XCTestCase {

    private func prompt(
        capture: Bool = false,
        channel: Bool = true,
        cloud: Bool = true,
        ended: ScreenContextEndReason? = nil,
        clipboard: ClipboardReplyGap = .nothingCopied
    ) -> ScreenContextPrompt {
        ScreenContextPrompt(
            capturePermitted: capture,
            canReachChannel: channel,
            cloudConfigured: cloud,
            ended: ended,
            clipboard: clipboard)
    }

    // MARK: The shipping build, with capture switched off

    /// The two sentences a shipping build can actually print, and they are
    /// different pieces of work: one is "copy something", the other is "the thing
    /// you copied is one tap inside this keyboard away".
    func testTheTwoClipboardRefusalsSayDifferentThings() {
        let empty = prompt(clipboard: .nothingCopied)
        let pending = prompt(clipboard: .copyNotRead)

        XCTAssertEqual(empty.title, "Nothing to reply to")
        XCTAssertEqual(pending.title, "Paste it in first")
        XCTAssertNotEqual(empty.detail, pending.detail)

        XCTAssertTrue(
            empty.detail.localizedCaseInsensitiveContains("copy"),
            "the empty refusal never says to copy anything: \(empty.detail)")
        XCTAssertTrue(
            pending.detail.contains("Paste"),
            "the pending refusal never names the control that lets the copy in: \(pending.detail)")
    }

    /// **The remedy is only on the refusal a control can clear.** Nothing inside
    /// the keyboard fixes an empty clipboard, so offering a button there would be
    /// a chip that leads somewhere with nothing in it.
    func testOnlyTheUnreadCopyOffersAWayIntoCopyClip() {
        XCTAssertTrue(prompt(clipboard: .copyNotRead).offersCopyClip)
        XCTAssertFalse(prompt(clipboard: .nothingCopied).offersCopyClip)
        XCTAssertEqual(
            ActionBanner.blockedTrailing(for: .copyclip), .dismissAndOpenCopyClip)
    }

    /// **The whole point of the flag.** Every state a shipping build can be in
    /// has to answer false here, or ReplayKit's picker is back under the Reply
    /// key. The broken build is the one that ignores `capturePermitted`, which
    /// answers true for the last of these.
    func testNoRefusalOffersABroadcastWhileCaptureIsOff() {
        let states: [ScreenContextPrompt] = [
            prompt(),
            prompt(channel: false),
            prompt(cloud: false),
            prompt(ended: .stopped),
            prompt(ended: .notConfigured),
            prompt(clipboard: .copyNotRead)
        ]
        for state in states {
            XCTAssertFalse(state.offersPicker, "\(state.title) offers to start a broadcast")
        }
    }

    /// An ending is news about a capture session, and with capture off there is
    /// nothing the owner of the phone could do with it — "Start it again" over a
    /// build that cannot start one is a dead end. It is skipped, and the
    /// clipboard's sentence is printed instead.
    func testAnEndingIsNotPrintedWhileCaptureIsOff() {
        let ended = prompt(ended: .notConfigured, clipboard: .nothingCopied)
        XCTAssertEqual(ended.title, "Nothing to reply to")
        XCTAssertFalse(
            ended.detail.localizedCaseInsensitiveContains("screen"),
            "a shipping build still names screen context at the user: \(ended.detail)")
    }

    // MARK: The two refusals that outrank the source either way

    /// Full Access comes first, because without the App Group the keyboard has no
    /// session token and cannot make a single cloud call — and unlike the status
    /// below it, it names something the owner of the phone can actually go and do.
    func testFullAccessComesFirstInBothBuilds() {
        for capture in [true, false] {
            let noChannel = prompt(capture: capture, channel: false, cloud: false)
            XCTAssertEqual(noChannel.title, "Needs Full Access")
            XCTAssertTrue(noChannel.detail.contains("Full Access"))
            XCTAssertFalse(noChannel.offersPicker)
            XCTAssertFalse(noChannel.offersCopyClip)
            XCTAssertEqual(
                prompt(capture: capture, channel: false, cloud: true).detail,
                noChannel.detail,
                "the cloud answer changed a refusal that is about the container")
        }
    }

    /// Every source ends at the same cloud call, so a dead backend refuses ahead
    /// of all of them — including ahead of a clip that is sitting there ready.
    func testNoConnectionOutranksTheClipboard() {
        let noCloud = prompt(cloud: false, clipboard: .copyNotRead)
        XCTAssertEqual(noCloud.title, "Not connected")
        XCTAssertTrue(
            noCloud.detail.contains(BackendTransport.setUpRecovery),
            "it does not say what would make it work: \(noCloud.detail)")
        // Names the state, not the component. See
        // `CloudModelSettingNameTests.testNoDeadEndNamesTheCloudModelAtTheUser`.
        XCTAssertFalse(
            noCloud.detail.localizedCaseInsensitiveContains("cloud model"),
            "the prompt names a component the user has never been shown: \(noCloud.detail)")
        XCTAssertFalse(noCloud.offersCopyClip, "a paste cannot fix a missing connection")
    }

    // MARK: The capture half, kept alive for the day NIT-6 passes

    /// The defect this type was written for. The broken version is
    /// `canReachChannel && (ended?.canRestart ?? true)`, which is `true` here — a
    /// keyboard on a stock install offering to record the user's screen for a
    /// session that cannot outlive the countdown.
    func testThePickerIsWithheldWhenThereIsNoBackend() {
        let withoutCloud = prompt(capture: true, cloud: false)
        XCTAssertFalse(
            withoutCloud.offersPicker,
            "the keyboard offers to start a broadcast that iOS ends inside a second")
        XCTAssertEqual(withoutCloud.title, "Not connected")
    }

    /// The other half, and it is not redundant: a version that simply never
    /// offered the start would pass the test above and leave Reply a dead end
    /// once the flag flips. The start is ReplayKit on the Reply key.
    func testThePickerIsOfferedWhenABroadcastCouldActuallyRun() {
        let ready = prompt(capture: true)
        XCTAssertTrue(ready.offersPicker)
        XCTAssertEqual(ready.title, "Screen context is off")
        XCTAssertTrue(
            ready.detail.contains("Start Broadcast"),
            "the sentence no longer names the system sheet: \(ready.detail)")
        XCTAssertTrue(
            ready.detail.hasPrefix("Tap"),
            "the sentence no longer tells them to tap: \(ready.detail)")
        XCTAssertTrue(
            ready.detail.contains("aBitBetterKeyboard"),
            "the way in is not named: \(ready.detail)")
        XCTAssertFalse(ready.offersCopyClip, "two remedies on one refusal")
    }

    /// An ending a restart cannot fix prints the page's own two sentences, the
    /// same pair the strip prints, so the app and the keyboard cannot disagree
    /// about one recorded ending.
    func testAnUnrestartableEndingPrintsThePagesOwnWords() {
        let deadEnding = prompt(capture: true, ended: .notConfigured)
        XCTAssertFalse(deadEnding.offersPicker)
        XCTAssertEqual(deadEnding.title, "Can't run yet")
        XCTAssertEqual(
            deadEnding.detail,
            "\(ScreenContextEndReason.notConfigured.explanation)\n"
                + ScreenContextEndReason.notConfigured.recovery,
            "the panel and the strip have to print one page's ending the same way")
    }

    /// An ending a restart *would* fix still offers the restart, so the guard
    /// added for the backend has not quietly disabled the ordinary case.
    func testAnEndingARestartFixesStillOffersThePicker() {
        for reason in [ScreenContextEndReason.stopped, .lost, .noFrames, .notEnded] {
            XCTAssertTrue(
                prompt(capture: true, ended: reason).offersPicker,
                "\(reason) is fixed by starting another one")
        }
    }
}
