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

    /// What the strip says when the build has no backend. The same sentence
    /// whether the tap is refused before a read or fails at the start of one.
    static let notConfigured = "Screen reading is not set up in this build."

    /// One request, claimed. Carries the frame it is to be answered about,
    /// because by the time the read returns the current frame is a different one.
    public struct Ticket: Sendable {
        public let sequence: UInt64
        public let identity: FrameIdentity
        public let capturedAt: UInt64
    }

    private struct State {
        var sessionID: UUID?
        /// The highest `intent.readNow` this session has acted on, in any way.
        /// Seeded at `begin` from whatever the page already held, so a request
        /// raised at a keyboard that is no longer waiting is never served.
        var seen: UInt64 = 0
        var isReading = false
        /// The sequence the in-flight read will stamp its record with. Raised by
        /// a request that arrives while it runs.
        var answering: UInt64 = 0
    }

    private let channel: CaptureChannelWriter
    private let reader: Runner?
    private let state = OSAllocatedUnfairLock(initialState: State())

    private static let log = Logger(subsystem: "com.nitai.aikeyboard", category: "CaptureRead")

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
            reader: BackendTransport.configured().map { CloudScreenReader(transport: $0) })
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

    // MARK: - The trigger

    /// Whether this sampled frame is the one that answers a raised request.
    ///
    /// Called from ReplayKit's delivery callback for every sampled frame, and it
    /// is a page load, a comparison and a lock — nothing that allocates. A ticket
    /// back means: encode this frame and hand it to `start`.
    public func claim(
        intent: CaptureIntent?, identity: FrameIdentity, capturedAt: UInt64,
        now: UInt64 = CaptureClock.now()
    ) -> Ticket? {
        guard let intent, intent.readNow > 0 else { return nil }

        enum Outcome {
            case ignore
            case stale
            case notConfigured
            case inFlight
            case read
        }

        var sequence: UInt64 = 0
        let outcome: Outcome = state.withLock { state in
            guard intent.readNow > state.seen else { return .ignore }
            sequence = intent.readNow
            state.seen = intent.readNow

            guard CaptureClock.elapsed(since: intent.readRequestedAt, now: now) <= Self.requestWindow
            else { return .stale }
            guard reader != nil else { return .notConfigured }
            guard !state.isReading else {
                state.answering = intent.readNow
                return .inFlight
            }
            state.isReading = true
            state.answering = intent.readNow
            return .read
        }

        switch outcome {
        case .ignore:
            return nil
        case .stale:
            // Counted as requested and never started, which is what the gap
            // between `readsRequested` and `readsStarted` means on a device run.
            channel.count(\.readsRequested)
            Self.log.notice("read refused: request \(sequence, privacy: .public) is older than the window")
            return nil
        case .notConfigured:
            channel.count(\.readsRequested)
            publish(
                sequence: sequence, identity: identity, capturedAt: capturedAt,
                outcome: .failed, detail: Self.notConfigured)
            return nil
        case .inFlight:
            channel.count(\.readsRequested)
            channel.count(\.refusedInFlight)
            Self.log.notice(
                "read folded: request \(sequence, privacy: .public) into the read already running")
            return nil
        case .read:
            channel.count(\.readsRequested)
            return Ticket(sequence: sequence, identity: identity, capturedAt: capturedAt)
        }
    }

    /// Performs the read for a claimed ticket, off the delivery queue.
    ///
    /// `jpeg` is all that crosses: the frame was reduced and encoded inside
    /// `processSampleBuffer` and no pixel buffer, downscale destination or
    /// `CGImage` is reachable from here. It is released when this returns.
    /// Wiping it first would be theatre — `BackendTransport` base64-encodes a
    /// second copy into the request body, and that one belongs to `URLSession`.
    public func start(_ ticket: Ticket, jpeg: Data) {
        guard let reader else {
            finish(ticket, outcome: .failed, detail: Self.notConfigured)
            return
        }

        channel.count(\.readsStarted)
        Self.log.notice(
            """
            read started request=\(ticket.sequence, privacy: .public) \
            bytes=\(jpeg.count, privacy: .public)
            """
        )

        Task { [weak self] in
            do {
                let output = try await reader.read(jpeg: jpeg)
                guard let self else { return }
                if let reading = output.value {
                    finish(ticket, reading: reading, provenance: output.provenance)
                } else {
                    finish(
                        ticket, outcome: .nothing,
                        detail: "There's nothing on this screen to reply to.")
                }
            } catch {
                self?.finish(ticket, outcome: .failed, detail: Self.explain(error))
            }
        }
    }

    /// The frame could not be turned into bytes. A claimed request is answered
    /// either way, because the keyboard is already waiting on its sequence.
    public func fail(_ ticket: Ticket, detail: String) {
        finish(ticket, outcome: .failed, detail: detail)
    }

    // MARK: - Publishing

    private func finish(
        _ ticket: Ticket,
        outcome: ScreenReadOutcome = .read,
        detail: String = "",
        reading: ScreenReading? = nil,
        provenance: AIProvenance = .cloud
    ) {
        // The sequence is taken at completion rather than from the ticket: a
        // request that arrived while this read ran was folded into it, and the
        // record has to carry the number the keyboard is waiting on.
        let sequence = state.withLock { state -> UInt64 in
            state.isReading = false
            return max(state.answering, ticket.sequence)
        }

        publish(
            sequence: sequence, identity: ticket.identity, capturedAt: ticket.capturedAt,
            outcome: outcome, detail: detail, reading: reading, provenance: provenance)
    }

    private func publish(
        sequence: UInt64,
        identity: FrameIdentity,
        capturedAt: UInt64,
        outcome: ScreenReadOutcome,
        detail: String,
        reading: ScreenReading? = nil,
        provenance: AIProvenance = .cloud
    ) {
        guard let session = state.withLock({ $0.sessionID }) ?? channel.status()?.sessionID else {
            Self.log.error("read finished with no session to publish it under")
            return
        }

        let record = ScreenReadingRecord(
            sessionID: session,
            requestSequence: sequence,
            frameIdentity: identity,
            capturedAt: capturedAt,
            readAt: CaptureClock.now(),
            provenance: Self.name(of: provenance),
            outcome: outcome,
            detail: detail,
            sender: reading?.sender ?? "",
            message: reading?.message ?? "",
            language: reading?.language.rawValue ?? "")

        do {
            try channel.publish(record)
            channel.count(\.readsCompleted)
            // The message itself is never logged. The unified log is readable by
            // anything with the device paired, and the whole point of this
            // pipeline is that a private conversation stays between the model and
            // the user.
            Self.log.notice(
                """
                read finished request=\(sequence, privacy: .public) \
                outcome=\(outcome.rawValue, privacy: .public) \
                sender=\(reading == nil ? "none" : "named", privacy: .public)
                """
            )
        } catch {
            Self.log.error("read could not be published: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func name(of provenance: AIProvenance) -> String {
        switch provenance {
        case .onDevice: return "onDevice"
        case .onDeviceBestEffort: return "onDeviceBestEffort"
        case .cloud: return "cloud"
        }
    }

    /// A sentence for the strip. Every error this can see already carries one,
    /// and the fallback names the operation rather than the exception.
    private static func explain(_ error: any Error) -> String {
        switch error {
        case let error as AIEngineError:
            return error.message
        case ScreenReadError.needsFullAccess:
            return "Screen reading needs Full Access to reach the network."
        case ScreenReadError.noCloudReader:
            return Self.notConfigured
        case ScreenReadError.network(let detail):
            return detail.isEmpty ? "The screen reader could not be reached." : detail
        case ScreenReadError.failed(let detail):
            return detail.isEmpty ? "The screen could not be read." : detail
        default:
            return "The screen could not be read."
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
private actor Runner {

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
