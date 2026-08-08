import Foundation

/// Why a capture session stopped, as far as anything in this app can know.
///
/// **Three cases, and the shortness of that list is the finding.** An earlier
/// version carried five more — `.deviceLocked`, `.phoneCall`, `.interrupted`,
/// `.contentResized`, `.carPlay` — mapped from `RPRecordingErrorCode`, and a
/// sixth, `.overBudget`, for a read budget that was never built. Nothing could
/// write any of them, and nothing ever will on this architecture. Read out of
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
/// So the reason a session ended is not information the capture process has. It
/// is told *that* the broadcast finished, never why, and inventing a cause from
/// that — which is what writing `.userStopped` unconditionally did — put a
/// sentence in front of the user that nothing had checked.
///
/// What is left is what can be observed: a broadcast that ended (`.stopped`) and
/// a producer that stopped answering (`.lost`, inferred by the reader from a
/// heartbeat that went stale, which is all a jetsam kill leaves behind).
public enum ScreenContextEndReason: UInt8, Codable, Sendable, CaseIterable {
    /// Still running, or never started. The zero value, so a freshly zeroed page
    /// does not claim an ending.
    case none = 0
    /// `broadcastFinished()` fired. The user stopped it from Control Center, or
    /// iOS ended it for a call, the lock button or something else — see the type's
    /// note: this side is not told which, so this case does not claim one.
    case stopped = 1
    /// Nothing reported an ending and the heartbeat went stale. A jetsam kill at
    /// the memory limit calls no callback at all, so this is the only case that
    /// covers it, and it is inferred by the reader rather than written by the
    /// producer.
    case lost = 2

    /// Shown to the user. Every one of these is a sentence the strip can print
    /// next to a restart affordance, and none of them names a cause that was not
    /// checked.
    public var explanation: String {
        switch self {
        case .none: return "Screen context is off."
        case .stopped: return "Screen context stopped."
        case .lost: return "Screen context stopped unexpectedly."
        }
    }
}
