import Dispatch
import Foundation
import os

/// The read: one cloud call per raised request, taken off the delivery path.
///
/// The capture process is a shutter with a phone line. `processSampleBuffer`
/// fingerprints frames at 4 Hz and reads nothing; the only thing that ever
/// triggers a read is `intent.readNow` going up, which is the user tapping
/// Reply. This class is the whole of that trigger, and the rules it enforces are
/// the ones that keep a 60 fps callback and a ~50 MB ceiling compatible with a
/// five-second network round trip.
///
/// **One read per raised request, and never two at once.** The delivery callback
/// calls `claim(intent:identity:capturedAt:now:)` on every sampled frame. It
/// returns a ticket only when the sequence in the shared page is higher than
/// anything this session has acted on. There is no read on frame arrival, no
/// retry, no timer and no speculative read — §5.1 of the capture design is why,
/// and it is not a setting.
///
/// **A request raised while a read is running is folded into it rather than
/// starting a second one.** The container holds exactly one `reading.json`, so a
/// second read would have nowhere to put its answer that did not overwrite the
/// first, and the keyboard matches on `requestSequence >= its own`. The in-flight
/// read therefore answers the newest request too, and `refusedInFlight` counts
/// that it happened. This is safe because the sequence is not what protects the
/// user: `CaptureFreshness` condition 4 compares the frame identity in the record
/// against the frame on screen *now*, so a folded answer about a screen the user
/// has left is refused by the gate rather than shown.
///
/// **Every ending is published.** A read that fails, a screen with nothing worth
/// replying to, a build with no backend configured — each writes a record
/// carrying the sequence that asked for it and a sentence saying what happened.
/// Silence is not an option: the keyboard waits twelve seconds for a record with
/// its own sequence, so a failure that says nothing is indistinguishable from a
/// capture process that is not running.
///
/// Nothing in here can be exercised against a real broadcast on this machine.
/// The iOS Simulator runtime ships no `replayd`, so `SampleHandler` is never
/// called; `ScreenReadServiceTests` drives this class directly with a fake
/// transport, which tests the read and not the delivery of frames to it.
public final class ScreenReadService: @unchecked Sendable {

    /// How long after `intent.readNow` was raised a request is still worth
    /// serving.
    ///
    /// Matched to the keyboard's own wait in `ScreenContextSession.contextForReply`:
    /// after that nobody is listening, and answering anyway would spend a cloud
    /// call and publish a record about a screen the user has long since left. It
    /// is also what stops a page left behind by a previous session — or by a
    /// previous boot, after which the monotonic clock has restarted below every
    /// timestamp in it — from firing a read the moment this one starts.
    public static let requestWindow = CaptureClock.nanoseconds(12)

    // Error messages, describesSetup, and explain are in ScreenReadService+ErrorMessages.swift.
    // claim, start, and fail are in ScreenReadService+Trigger.swift.
    // finish, publish, and name are in ScreenReadService+Publishing.swift.

    /// One request, claimed. Carries the frame it is to be answered about,
    /// because by the time the read returns the current frame is a different one.
    public struct Ticket: Sendable {
        public let sequence: UInt64
        public let identity: FrameIdentity
        public let capturedAt: UInt64
    }

    struct State {
        var sessionID: UUID?
        /// The highest `intent.readNow` this session has acted on, in any way.
        /// Seeded at `begin` from whatever the page already held, so a request
        /// raised at a keyboard that is no longer waiting is never served.
        var seen: UInt64 = 0
        var isReading = false
        /// The sequence the in-flight read will stamp its record with. Raised by
        /// a request that arrives while it runs.
        var answering: UInt64 = 0
        /// The screen the in-flight read is *about*. A second tap can only be
        /// folded into a read whose answer would actually answer it, and that is
        /// exactly the question this settles — see `claim`.
        var readingIdentity: FrameIdentity = .absent
        /// The last sequence a deferral was logged for. A deferred request is
        /// re-offered by every sampled frame until the running read releases the
        /// flag, which is four a second for the length of a cloud call; without
        /// this the extension writes twenty identical lines per tap.
        var lastDeferred: UInt64 = 0
    }

    let channel: CaptureChannelWriter
    let reader: Runner?
    let state = OSAllocatedUnfairLock(initialState: State())

    static let log = Logger(subsystem: "com.nitai.aikeyboard", category: "CaptureRead")

    /// A nil `reader` is a build with no backend configured, and it is a state
    /// rather than an error: the extension keeps fingerprinting, and every Reply
    /// tap is answered with a record that says screen reading is not set up.
    /// Failing at construction would leave the keyboard waiting out its timeout
    /// with nothing to show.
    public init(channel: CaptureChannelWriter, reader: CloudScreenReader?) {
        self.channel = channel
        self.reader = reader.map(Runner.init(reader:))
    }

    /// The shipping configuration: the backend URL the app wrote to the shared
    /// store. The capture process holds no provider credential, for the same
    /// reason the keyboard does not — anything in the bundle is extractable.
    public static func standard(channel: CaptureChannelWriter) -> ScreenReadService {
        ScreenReadService(
            channel: channel,
            // Gated on `isReady`, not on `configured()`. `canRead` is what
            // `SampleHandler.broadcastStarted` consults before it lets a broadcast
            // live, and a build that ships an address makes `configured()` true
            // from the first launch — so without this the user grants screen
            // recording, iOS shows the red pill, a frame is captured and uploaded,
            // and the first read comes back 401 because no token has been pasted
            // in. Refusing at `broadcastStarted` costs a tap; the alternative
            // records somebody's screen for nothing.
            reader: (BackendTransport.isReady() ? BackendTransport.configured() : nil)
                .map { CloudScreenReader(transport: $0) })
    }

    /// True when a backend is configured and a read could actually be performed.
    public var canRead: Bool { reader != nil }

    // MARK: - Session

    /// Starts a session's worth of state.
    ///
    /// `intent` is the page as it stands *now*, and seeding from it is the point:
    /// the keyboard's request sequence lives in a file that outlives both
    /// processes, so a session that started from zero would answer the last tap
    /// of an hour ago with a screenshot of whatever is on screen when it starts.
    public func begin(session: UUID, intent: CaptureIntent?) {
        state.withLock {
            $0 = State(sessionID: session, seen: intent?.readNow ?? 0)
        }
    }
}

// MARK: - The serial queue

/// The read's execution context, and the reason it has one.
///
/// `processSampleBuffer` is the 60 fps delivery callback. A five-second cloud
/// round trip inside it stalls delivery for five seconds, and while delivery is
/// stalled the extension observes no frames — which is precisely the hole
/// `CaptureFreshness` condition 3 exists to close, since the identity in the
/// page would freeze at the frame being read while the heartbeat kept ticking.
/// So the call runs on this serial queue instead, delivery keeps advancing the
/// fingerprint throughout, and a reading is normally confirmed within one 250 ms
/// sample of the read returning.
actor Runner {

    private let queue = DispatchSerialQueue(
        label: "com.nitai.aikeyboard.capture.read", qos: .userInitiated)
    private let reader: CloudScreenReader

    nonisolated var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }

    init(reader: CloudScreenReader) {
        self.reader = reader
    }

    func read(jpeg: Data) async throws -> AIOutput<ScreenReading?> {
        try await reader.read(jpeg: jpeg)
    }
}
