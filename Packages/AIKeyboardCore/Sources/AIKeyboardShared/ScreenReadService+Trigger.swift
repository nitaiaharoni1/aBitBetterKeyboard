import Foundation
import os

// MARK: - The trigger

extension ScreenReadService {

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
            /// A tap about a screen the running read is not about. Deliberately
            /// left unclaimed and unmarked, so the next frame after that read
            /// finishes serves it for real.
            case supersedes
            /// The same, on every frame after the first. Identical behaviour,
            /// silent: the deferral is re-offered four times a second for the
            /// length of a cloud call, and saying so twenty times says nothing the
            /// first line did not.
            case supersedesQuietly
            case read
        }

        var sequence: UInt64 = 0
        let outcome: Outcome = state.withLock { state in
            guard intent.readNow > state.seen else { return .ignore }
            sequence = intent.readNow

            guard CaptureClock.elapsed(since: intent.readRequestedAt, now: now) <= Self.requestWindow
            else {
                state.seen = intent.readNow
                return .stale
            }
            guard reader != nil else {
                state.seen = intent.readNow
                return .notConfigured
            }
            guard !state.isReading else {
                // **A tap is folded into the running read only when that read is
                // about the same screen.** Folding is right when the user taps
                // twice on one conversation: the answer already coming back
                // answers both, and a second cloud call would be waste.
                //
                // It is wrong the moment the screen has moved on. A cloud read
                // takes about five seconds, which is long enough to leave one
                // conversation and open another, and the record the running read
                // publishes carries the *old* frame's identity. `CaptureFreshness`
                // refuses it — correctly, it describes a screen the user is no
                // longer looking at — so the tap produces nothing.
                //
                // Advancing `seen` here is what made that permanent: no later
                // frame could satisfy `readNow > seen`, so the request could never
                // be picked up once the read finished, and the keyboard sat out
                // its full twelve seconds while frames of the new conversation
                // went by unread. Only a third tap recovered it. So `seen` is left
                // alone on a changed screen, and the first frame sampled after
                // this read completes claims it properly.
                // `answering` is raised only on the fold. A read of the previous
                // screen is not answering this tap, and stamping its record with
                // this sequence would hand the waiting keyboard a record it has
                // to refuse before the real answer arrives.
                guard identity == state.readingIdentity else {
                    let firstTime = state.lastDeferred != intent.readNow
                    state.lastDeferred = intent.readNow
                    return firstTime ? .supersedes : .supersedesQuietly
                }
                state.answering = intent.readNow
                state.seen = intent.readNow
                return .inFlight
            }
            state.seen = intent.readNow
            state.isReading = true
            state.answering = intent.readNow
            state.readingIdentity = identity
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
        case .supersedes:
            // Counted nowhere yet, on purpose: this request has not been served
            // and will come back through this same path once the running read
            // releases `isReading`. Counting it here would report two requests
            // for the user's one tap.
            Self.log.notice(
                """
                read deferred: request \(sequence, privacy: .public) is about a different \
                screen than the read already running
                """)
            return nil
        case .supersedesQuietly:
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
}
