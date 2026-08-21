import XCTest

@testable import AIKeyboardShared

extension XCTestCase {

    /// Takes back the `SecureDecisionRecord` this test case wrote into the real
    /// App Group container.
    ///
    /// **Every test that reaches `ScreenContextSession.permitsRead` needs this,
    /// and reaching it is easier than it looks.** The direct route is calling
    /// `permitsRead` itself; the indirect one is `controller.run(.reply)` with a
    /// clip in the CopyClip ledger, which is what `SparkleReachabilityTests` and
    /// `ReplySourceTests` do. Both write, because `note(_:)` resolves
    /// `SharedContainer.url` and has no test seam — and the simulator hands
    /// `AIKeyboardCoreTests` a real App Group container even though the target
    /// carries no entitlement, which is the standing finding
    /// `KeyboardMemoryPeakTests` records.
    ///
    /// Left alone, the suite leaves a "Reply and secure fields" row in the
    /// simulator's own Settings describing taps nobody made. That is the same
    /// family as the suite once teaching `PersonalLanguageModel` the word `Handi`
    /// ten times and `Nitai` nine, which quietly stopped
    /// `PersonalDictionaryTests` from being able to prove anything.
    ///
    /// **The drain is not optional.** `note(_:)` dispatches onto a serial queue,
    /// so a delete that did not wait would race the write and lose about as often
    /// as it won. `waitForPendingWrites()` is `queue.sync {}` on that same serial
    /// queue, so it cannot run until everything queued ahead of it has finished.
    ///
    /// It lives here as one extension rather than as three copies because the
    /// next test to reach `permitsRead` will not know it has to remember this.
    func removeSecureDecisionRecord() {
        SecureDecisionRecord.waitForPendingWrites()
        guard let url = SecureDecisionRecord.url else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
