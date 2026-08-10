import Combine
import CoreGraphics
import Foundation
import UIKit

/// What the keyboard and the app both look at to answer "what is screen context
/// doing right now", and the one place a reading is turned into an offer.
///
/// It has two sources and they are not equals.
///
/// **A real capture session, through `ScreenContextChannel`.** A ReplayKit
/// broadcast upload extension samples frames and publishes a `CaptureStatus`
/// page; this class polls it, runs `CaptureFreshness` over what it finds, and
/// publishes the verdict as a `ScreenContextState`. Nothing here decides
/// freshness itself, and nothing here shows a reading the gate refused.
///
/// **The scripted demo**, which is what `start()` runs. It exists for the in-app
/// playground and the UI walkthrough, and it never wins: the moment a real
/// session appears on the channel, the script is cancelled and the truth is
/// published instead. `source` says which one the state came from, so no screen
/// has to guess.
///
/// **Nothing in either path can be exercised against a real broadcast on this
/// machine.** The iOS Simulator runtime ships no `replayd`, so no broadcast
/// session starts, `AIKeyboardBroadcast` is never launched and the channel is
/// only ever fed here by `CaptureChannelProbe` under
/// `Scripts/prove-capture-channel.sh`. Every claim about what a real session
/// does needs a device.
@MainActor
public final class ScreenContextSession: ObservableObject {

    /// Where the published state came from.
    public enum Source: Equatable, Sendable {
        case none
        /// The scripted timeline. Only reachable from the app.
        case scripted
        /// A capture session on the other end of the channel.
        case capture
    }

    public static let shared = ScreenContextSession()

    // `internal(set)` so the file-split extensions (`+Reply`, `+Consuming`,
    // `+ScriptedDemo`) can mutate these; outside the module they stay read-only.
    @Published public internal(set) var state: ScreenContextState = .off
    @Published public internal(set) var source: Source = .none

    /// Frames the capture process has sampled this session, or the scripted
    /// count. Shown in the app beside the number of screens actually sent.
    @Published public internal(set) var framesRead = 0

    /// The capture process's own counters, or nil when no session has ever run
    /// against this container. The app screen renders them directly rather than
    /// paraphrasing.
    @Published public internal(set) var status: CaptureStatus?

    /// When the session started, for the running-time label.
    @Published public internal(set) var startedAt: Date?

    /// The last Reply tap could not be met, so the strip must stop promising it
    /// can.
    ///
    /// **This is the consumer's own observation, not a guess about the other
    /// process**, and it exists because the strip was making a promise the build
    /// could not keep: it said "Reply can read this screen" while nothing in the
    /// capture process could read one. That half is written now — a tap makes
    /// `AIKeyboardBroadcast` encode one frame and call `CloudScreenReader` — but
    /// the flag stays, because it never encoded the *reason*, only the fact that
    /// a raised request went unanswered. It is still the honest signal when a
    /// broadcast is not really running, when the read fails silently, or when
    /// ReplayKit turns out not to deliver what this build assumes.
    ///
    /// **It now also covers a read that *was* answered, with a failure about the
    /// setup**, which is wider than the name — kept because the name is mirrored
    /// into `KeyboardController` and read by two views, and the behaviour matters
    /// more than the noun. A rejected access token fails the same way on every
    /// tap; leaving the offer up meant each of those taps uploaded another
    /// picture of the user's screen to be refused identically.
    /// `ScreenReadService.describesSetup` is the test, and it is identity against
    /// three constants rather than a parser.
    ///
    /// Keying the copy off what actually happened, rather than off a hard-coded
    /// "not built", keeps it true on both sides of that work landing: the first
    /// answered read clears it, and a new broadcast clears it too, because the
    /// last session failing says nothing about this one.
    @Published public internal(set) var lastReadWentUnanswered = false

    /// How long after the last heartbeat an ending is still worth showing.
    ///
    /// **A guess, and it is here for a case the freshness gate cannot see.** A
    /// page whose producer died is `.ended(.lost)` for ever afterwards, so
    /// without this a strip would say "screen context stopped unexpectedly,
    /// restart it" days later, about a session the user has long forgotten. Ten
    /// minutes is chosen to be far longer than the gap between a jetsam kill and
    /// the user's next keyboard appearance — the case §8.2 exists for, where the
    /// consumer never saw the session alive — and short enough that yesterday's
    /// page reads as off. A reboot resolves it without the constant, because
    /// `CaptureClock` restarts below every timestamp in the page and
    /// `CaptureClock.elapsed` reports a future timestamp as infinitely old.
    static let endingWorthShowing = CaptureClock.nanoseconds(600)

    var sampleIndex = 0
    var task: Task<Void, Never>?
    var channel: ScreenContextChannel?
    var cancellable: AnyCancellable?

    /// Which process this session consumes as. Only the keyboard may raise a
    /// real read; see `contextForReply`.
    var role: ScreenContextChannel.Role = .keyboard
    /// The session this consumer has seen alive. An ending is always news for
    /// that one, however long ago the heartbeat stopped.
    var sessionSeenLive: UUID?

    /// Reads frames handed to `submit(_:appName:appIcon:)`. Nil leaves the
    /// session on the scripted timeline below, which is what the in-app
    /// playground and the UI tests drive.
    public var reader: (any ScreenReader)?

    /// Whether a screen-reading backend is set up, asked the same way the capture
    /// process asks it. Only `isWorthReporting` reads it, and only for
    /// `.notConfigured`.
    ///
    /// A closure rather than a direct call so a test can drive both answers:
    /// `BackendTransport.configured()` reads the App Group suite, which a test
    /// bundle shares with every other test in the process, and a test that wrote
    /// a real backend URL into it would leak into the ones that assert there is
    /// none.
    var isScreenReadingConfigured: () -> Bool = { BackendTransport.isReady() }

    /// The app and the keyboard each have exactly one of these. Internal rather
    /// than private so a test can drive an isolated session against an isolated
    /// channel; nothing outside this module builds a second one.
    init() {}

    public var isLive: Bool { state.isLive }

    /// Whether the sample conversation can be played right now.
    ///
    /// False for exactly one reason, and it is a reason the user can act on: a
    /// capture session is watching the screen, and a scripted message painted
    /// over a live one would put a sentence nobody sent where a real one belongs.
    /// The screen that offers the sample renders this as a sentence rather than
    /// as a disabled button with no explanation.
    public var canPlaySample: Bool { !(source == .capture && state.isLive) }
}
