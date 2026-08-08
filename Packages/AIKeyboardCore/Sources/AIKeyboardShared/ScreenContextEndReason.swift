import Foundation

/// Why a capture session stopped.
///
/// A first-class value rather than an absence, because "screen context stopped
/// because you took a call" and "…because it ran out of memory" are a normal
/// event and a bug report, and the strip has to be able to say which.
///
/// The five middle cases are `RPRecordingErrorCode`, verified in `RPError.h` of
/// `iPhoneOS26.2.sdk`. The codes are spelled out as integers here on purpose:
/// this type is read by the keyboard, which has no business linking ReplayKit,
/// and it is written by the broadcast extension, which is the only side that
/// does.
public enum ScreenContextEndReason: UInt8, Codable, Sendable, CaseIterable {
    /// Still running, or never started. The zero value, so a freshly zeroed page
    /// does not claim an ending.
    case none = 0
    /// The user stopped the broadcast from Control Center or the red pill.
    /// `broadcastFinished()` with no error.
    case userStopped = 1
    /// `RPRecordingErrorSystemDormancy`, -5809. The user pressed the power
    /// button.
    case deviceLocked = 2
    /// `RPRecordingErrorActivePhoneCall`, -5811.
    case phoneCall = 3
    /// `RPRecordingErrorInterrupted`, -5806. Another app interrupted it.
    case interrupted = 4
    /// `RPRecordingErrorContentResize`, -5807. Multitasking or a resize.
    case contentResized = 5
    /// `RPRecordingErrorCarPlay`, -5813.
    case carPlay = 6
    /// The session's read budget ran out and the extension stood itself down.
    case overBudget = 7
    /// Nothing reported an ending and the heartbeat went stale. A jetsam kill at
    /// the memory limit calls no callback at all, so this is the only case that
    /// covers it, and it is inferred by the reader rather than written by the
    /// producer.
    case lost = 8

    /// Maps a `RPRecordingErrorCode` raw value. Anything unrecognised is
    /// `.interrupted` rather than `.none`: the session did end, and reporting no
    /// reason for an ending that happened is worse than reporting a vague one.
    public init(recordingErrorCode code: Int) {
        switch code {
        case -5806: self = .interrupted
        case -5807: self = .contentResized
        case -5809: self = .deviceLocked
        case -5811: self = .phoneCall
        case -5813: self = .carPlay
        default: self = .interrupted
        }
    }

    /// Shown to the user. Every one of these is a sentence the strip can print
    /// next to a restart affordance.
    public var explanation: String {
        switch self {
        case .none: return "Screen context is off."
        case .userStopped: return "Screen context stopped."
        case .deviceLocked: return "Screen context stopped when the screen locked."
        case .phoneCall: return "Screen context stopped for a phone call."
        case .interrupted: return "Screen context was interrupted."
        case .contentResized: return "Screen context stopped when the screen resized."
        case .carPlay: return "Screen context stopped for CarPlay."
        case .overBudget: return "Screen context stopped: out of reads for today."
        case .lost: return "Screen context stopped unexpectedly."
        }
    }
}
