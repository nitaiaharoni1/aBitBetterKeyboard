import Foundation

/// Why a capture session stopped, as far as anything in this app can know.
///
/// **Every case here is one something writes, and the shortness of that list is
/// the finding.** An earlier version carried five more — `.deviceLocked`,
/// `.phoneCall`, `.interrupted`, `.contentResized`, `.carPlay` — mapped from
/// `RPRecordingErrorCode`, and a sixth, `.overBudget`, for a read budget that was
/// never built. Nothing could write any of them, and nothing ever will on this
/// architecture. Read out of
/// `RPBroadcastExtension.h` in `iPhoneOS26.2.sdk` on 2026-08-08:
///
/// - `broadcastFinished` is *"called when the RPBroadcastController finishBroadcast
///   method is called from the broadcasting application."* It takes no argument.
///   There is no callback anywhere on `RPBroadcastSampleHandler` that hands the
///   extension an `NSError`.
/// - `finishBroadcastWithError:` is a method the extension **calls**, not one it
///   receives: *"Method that should be called when broadcasting can not proceed
///   due to an error."* The error it carries is delivered to the broadcasting
///   app through `RPBroadcastControllerDelegate`.
/// - This app has no `RPBroadcastController`. Broadcasts are started from
///   `RPSystemBroadcastPickerView`, so there is no controller and no delegate for
///   a reason code to arrive at.
///
/// So the reason a session ended is not information the capture process has *from
/// iOS*. It is told *that* the broadcast finished, never why, and inventing a
/// cause from that — which is what writing `.userStopped` unconditionally did —
/// put a sentence in front of the user that nothing had checked.
///
/// **But "iOS did not tell us" is not the same as "nothing here knows anything",
/// and treating those as the same shipped a dead end.** The capture process
/// observes two things about its own session that are worth more to the phone's
/// owner than the bare word "stopped", and both are checked rather than guessed:
/// whether a screen reader was configured at all (`.notConfigured`), and whether
/// ReplayKit ever delivered a single frame (`.noFrames`). Those are the two ways
/// this pipeline can be switched on and still do nothing, and before they were
/// recorded both surfaced as `.stopped` — a sentence with no cause and no action,
/// which is exactly what a device reported.
///
/// So: two observed by the producer about iOS's behaviour (`.stopped`, `.lost`),
/// two observed by the producer about itself (`.notConfigured`, `.noFrames`), and
/// nothing invented. `.lost` is the only one inferred by the *reader*, from a
/// heartbeat that went stale, which is all a jetsam kill leaves behind.
public enum ScreenContextEndReason: UInt8, Codable, Sendable, CaseIterable {
    /// Still running, or never started. The zero value, so a freshly zeroed page
    /// does not claim an ending.
    ///
    /// **`notEnded` and not `none`, for the same reason `FrameIdentity` has
    /// `.absent`.** `status()` returns an optional, so `status()?.endReason` is a
    /// `ScreenContextEndReason?` — and in that position `.none` silently resolves
    /// to `Optional.none`, which is nil. `XCTAssertEqual(writer.status()?.endReason,
    /// .none)` therefore compiles, reads as "no ending was recorded", and asserts
    /// "there is no status page at all". It failed against a channel that was
    /// behaving correctly. That is the second time this exact collision has cost a
    /// test in this project; the raw value stays 0, so nothing on the wire moves.
    case notEnded = 0
    /// `broadcastFinished()` fired after at least one frame had arrived. The user
    /// stopped it from Control Center, or iOS ended it for a call, the lock button
    /// or something else — see the type's note: this side is not told which, so
    /// this case does not claim one.
    case stopped = 1
    /// Nothing reported an ending and the heartbeat went stale. A jetsam kill at
    /// the memory limit calls no callback at all, so this is the only case that
    /// covers it, and it is inferred by the reader rather than written by the
    /// producer.
    case lost = 2
    /// The session started with no screen reader behind it, so no Reply could
    /// ever have been answered. Written by `SampleHandler.broadcastStarted` when
    /// `ScreenReadService.canRead` is false, which happens whenever no backend URL
    /// has reached the shared store. The broadcast is finished immediately rather
    /// than left running: a system recording indicator over a feature that cannot
    /// work is worse than an explanation.
    case notConfigured = 3
    /// `broadcastFinished()` fired and `framesDelivered` was still zero. The
    /// broadcast was accepted, the extension ran, and ReplayKit handed it nothing
    /// — which is R1 in the capture design and has never been measured on hardware.
    /// Written by `SampleHandler.broadcastFinished`.
    case noFrames = 4

    /// What happened, in a sentence. None of these names a cause that was not
    /// checked.
    public var explanation: String {
        switch self {
        case .notEnded: return "Screen context is off."
        case .stopped: return "Screen context stopped."
        case .lost: return "Screen context stopped unexpectedly."
        // Names the cloud model rather than "screen reading … in this build",
        // because it is one setting serving two features and the sentence has to
        // survive being read by somebody who came here from a failed Hebrew
        // rewrite. See `BackendTransport.settingsPath`.
        case .notConfigured:
            return "Screen context stopped: the cloud model is not finished being set up, "
                + "and reading a screen needs it."
        case .noFrames: return "Screen context stopped without ever receiving the screen."
        }
    }

    /// What to do about it, in a sentence, written to read the same wherever it is
    /// printed.
    ///
    /// **It is part of the reason rather than part of the view on purpose.** The
    /// strip used to append a fixed "Restart it in AI Keyboard." to every ending
    /// and the app's Screen Context screen appended its own "Start it again
    /// below.", so the two surfaces gave different advice for the same page — and
    /// both gave advice that is wrong for an ending a restart cannot fix. Keeping
    /// the recovery beside the explanation is what makes "the app says the same
    /// thing the keyboard says" structural instead of a convention.
    public var recovery: String {
        switch self {
        case .notEnded, .stopped, .lost:
            return "Start it again."
        case .notConfigured:
            // Names a screen and a field that exist. It used to say "in AI
            // Keyboard's settings", where there was no such field and no writer
            // for the key anywhere in the app — an instruction the owner of the
            // phone could follow to a dead end, which is the same as no
            // instruction. Then it named Screen Context, which was true but was
            // half the story: the same key is what every Hebrew Fix, Rewrite,
            // Tone and Reply needs, and pointing two features at two different
            // names for one setting is how a user ends up believing there are
            // two. `BackendTransport.settingsPath` is the one name.
            return BackendTransport.setUpRecovery
        case .noFrames:
            return "Start it again. If it stops the same way, iOS is not handing the screen to this app."
        }
    }

    /// Whether starting another broadcast is worth offering. False only for
    /// `.notConfigured`, where a second broadcast would end the same way inside a
    /// second.
    public var canRestart: Bool { self != .notConfigured }

    // MARK: - The producer's two decisions
    //
    // **Here rather than in `SampleHandler`, and only because of what can be
    // tested.** `AIKeyboardBroadcast` is an app extension: `AIKeyboardCoreTests`
    // cannot import it, no simulator ships `replayd`, and `processSampleBuffer`
    // has never executed anywhere — so a decision written inline in that class is
    // a decision nothing can ever check. Both of these are pure functions of one
    // value each, which is exactly the shape that can live in a target the tests
    // reach. `SampleHandler` calls them and does the I/O around them.
    //
    // The seam that remains is that `SampleHandler` calls these at all, and no
    // test in this repository can assert that. `Scripts/prove-broadcast-extension.sh`
    // is where a check on the extension's own binary would go if it ever became
    // worth writing.

    /// The reason a session must not start, decided before the first frame, or
    /// nil to proceed.
    ///
    /// `canRead` is `ScreenReadService.canRead`: false whenever no backend URL has
    /// reached the shared store, which is the state a stock install is in. A
    /// broadcast in that state can never answer a Reply, so it is refused with a
    /// reason instead of running a system recording indicator over a feature that
    /// cannot work.
    public static func refusalToStart(canRead: Bool) -> ScreenContextEndReason? {
        canRead ? nil : .notConfigured
    }

    /// The reason to record when `broadcastFinished()` fires.
    ///
    /// iOS gives that callback no argument, so the only thing this side knows is
    /// what it observed: whether ReplayKit ever delivered anything. A session that
    /// ended having received nothing is R1 failing, which is a different sentence
    /// from a session the user stopped, and it used to be the same one.
    public static func ending(framesDelivered: UInt32) -> ScreenContextEndReason {
        framesDelivered == 0 ? .noFrames : .stopped
    }
}
