import XCTest

@testable import AIKeyboardCore

/// The end-reason enumeration: what each value means, what writes it, and what
/// it tells the user to do.
final class ScreenContextEndReasonTests: XCTestCase {

    /// **Every reason in this enumeration has something that writes it.**
    ///
    /// It used to carry eight, five of them mapped from `RPRecordingErrorCode`
    /// through an initialiser whose only caller was the test that exercised it,
    /// and a sixth for a read budget that was never built. Nothing could reach any
    /// of them: `broadcastFinished` takes no argument, `RPBroadcastSampleHandler`
    /// has no callback carrying an `NSError`, and `finishBroadcastWithError:` is a
    /// method the extension calls, whose error goes to an `RPBroadcastController`
    /// this app does not have. Meanwhile the Screen Context screen promised "this
    /// screen says which".
    ///
    /// This asserts the list rather than the mapping, because the list is the
    /// claim: re-adding a case means finding the code that writes it first.
    ///
    /// The two added since carry their writer in this list on purpose:
    /// `.notConfigured` is written by `SampleHandler.broadcastStarted` when
    /// `ScreenReadService.canRead` is false, and `.noFrames` by
    /// `SampleHandler.broadcastFinished` when the page's `framesDelivered` is still
    /// zero. Neither is inferred and neither is decorative.
    func testEveryEndReasonIsOneSomethingCanWrite() {
        XCTAssertEqual(
            ScreenContextEndReason.allCases, [.notEnded, .stopped, .lost, .notConfigured, .noFrames],
            "a reason nothing writes is a sentence the strip prints and nobody checked")
        XCTAssertEqual(
            ScreenContextEndReason.notEnded.rawValue, 0,
            "a zeroed page must not claim an ending")
        XCTAssertEqual(
            CaptureStatus().endReason, .notEnded,
            "and a zeroed page reads back as running, not as an unknown ending")

        var status = CaptureStatus()
        status.endReasonRaw = 200
        XCTAssertEqual(
            status.endReason, .lost,
            "a raw value from a build that knew more reasons than this one is still an ending")
    }

    /// The reason `broadcastFinished()` writes never names a cause, because that
    /// callback is not given one.
    ///
    /// The list is the three reasons whose cause iOS withholds. `.notConfigured`
    /// and `.noFrames` are excluded because they are the opposite case: each names
    /// something the capture process checked about itself before writing it, and a
    /// rule against naming causes would forbid exactly the two reasons that have
    /// one.
    func testTheRecordedStopDoesNotClaimWhoStoppedIt() {
        XCTAssertEqual(ScreenContextEndReason.stopped.explanation, "Screen context stopped.")
        for reason in [ScreenContextEndReason.notEnded, .stopped, .lost] {
            for cause in ["call", "lock", "CarPlay", "memory", "you", "user"] {
                XCTAssertFalse(
                    reason.explanation.localizedCaseInsensitiveContains(cause),
                    "\(reason) names a cause nothing measured")
                XCTAssertFalse(
                    reason.recovery.localizedCaseInsensitiveContains(cause),
                    "\(reason)'s recovery names a cause nothing measured")
            }
        }
    }

    /// **Every reason says what to do, and it says it in one place.**
    ///
    /// The strip appended a fixed "Restart it in AI Keyboard." to every ending and
    /// `ScreenContextView` appended its own "Start it again below." — two surfaces
    /// reading one page and giving different advice, both of it wrong for an
    /// ending a restart cannot fix. `recovery` is what makes them agree by
    /// construction. A view test cannot assert that from here, so this asserts the
    /// property the views rest on: the advice exists, it is not the explanation
    /// repeated, and the one reason a restart will not fix says so.
    func testEveryEndReasonCarriesItsOwnRecovery() {
        for reason in ScreenContextEndReason.allCases {
            XCTAssertFalse(
                reason.recovery.isEmpty, "\(reason) offers the user nothing to do")
            XCTAssertNotEqual(
                reason.recovery, reason.explanation,
                "\(reason) restates what happened instead of what to do about it")
            XCTAssertFalse(
                reason.explanation.isEmpty, "\(reason) is a silent ending")
        }

        XCTAssertFalse(
            ScreenContextEndReason.notConfigured.canRestart,
            "a second broadcast would end the same way inside a second")
        for reason in [ScreenContextEndReason.notEnded, .stopped, .lost, .noFrames] {
            XCTAssertTrue(reason.canRestart, "\(reason) is fixed by starting another one")
        }
    }

    /// **The producer's two decisions, against the versions they replaced.**
    ///
    /// Both used to be written inline in `SampleHandler.broadcastStarted` and
    /// `broadcastFinished`, where nothing can reach them: `AIKeyboardCoreTests`
    /// cannot import an app extension, and no simulator ships `replayd`. Moved into
    /// `ScreenContextEndReason` they are two pure functions of one value each, and
    /// each assertion below is chosen to reject the code that shipped before it:
    ///
    /// | Broken version | Returns | Asserted |
    /// |---|---|---|
    /// | no refusal at all | nil for `canRead: false` | `.notConfigured` |
    /// | `channel.end(.stopped)` unconditionally | `.stopped` for 0 frames | `.noFrames` |
    ///
    /// The two `nil`/`.stopped` cases are the other half of each pair — a decision
    /// that refused every session, or called every ending a failure, would be worse
    /// than the bug — and they are guards rather than the point.
    func testTheProducerNamesWhichWayASessionFailed() {
        XCTAssertEqual(
            ScreenContextEndReason.refusalToStart(canRead: false), .notConfigured,
            "a broadcast that can never answer a Reply was allowed to run anyway")
        XCTAssertNil(
            ScreenContextEndReason.refusalToStart(canRead: true),
            "a session with a reader behind it must not be refused")

        XCTAssertEqual(
            ScreenContextEndReason.ending(framesDelivered: 0), .noFrames,
            "a session ReplayKit never fed reads as an ordinary stop, which is R1 failing silently")
        XCTAssertEqual(
            ScreenContextEndReason.ending(framesDelivered: 1), .stopped,
            "one frame is enough: the pipeline worked and this ending names no cause")
    }
}
