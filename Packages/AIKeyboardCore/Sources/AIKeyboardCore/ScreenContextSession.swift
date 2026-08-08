import Combine
import CoreGraphics
import Foundation

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

    @Published public private(set) var state: ScreenContextState = .off
    @Published public private(set) var source: Source = .none

    /// Frames the capture process has sampled this session, or the scripted
    /// count. Shown in the app beside the number of screens actually sent.
    @Published public private(set) var framesRead = 0

    /// The capture process's own counters, or nil when no session has ever run
    /// against this container. The app screen renders them directly rather than
    /// paraphrasing.
    @Published public private(set) var status: CaptureStatus?

    /// When the session started, for the running-time label.
    @Published public private(set) var startedAt: Date?

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
    private static let endingWorthShowing = CaptureClock.nanoseconds(600)

    private var sampleIndex = 0
    private var task: Task<Void, Never>?
    private var channel: ScreenContextChannel?
    private var cancellable: AnyCancellable?
    /// The session this consumer has seen alive. An ending is always news for
    /// that one, however long ago the heartbeat stopped.
    private var sessionSeenLive: UUID?

    /// Reads frames handed to `submit(_:appName:appIcon:)`. Nil leaves the
    /// session on the scripted timeline below, which is what the in-app
    /// playground and the UI tests drive.
    public var reader: (any ScreenReader)?

    /// The app and the keyboard each have exactly one of these. Internal rather
    /// than private so a test can drive an isolated session against an isolated
    /// channel; nothing outside this module builds a second one.
    init() {}

    public var isLive: Bool { state.isLive }

    // MARK: - The real session

    /// Starts consuming a capture channel and publishing what it says.
    ///
    /// The keyboard calls this while it is on screen; the app's Screen Context
    /// screen calls it as an `.observer`, which reads the same page and writes
    /// nothing, because only the keyboard may claim the keyboard is visible.
    public func startConsuming(
        _ channel: ScreenContextChannel = .shared, as role: ScreenContextChannel.Role = .keyboard
    ) {
        self.channel = channel
        channel.startWatching(as: role)

        // `$verdict` is assigned on every poll, so this fires at the poll rate
        // even when the verdict has not moved — which is what carries a *new
        // reading* under an unchanged verdict. The published values this reads
        // back are the ones the same poll has already written; `verdict` itself
        // has not been assigned yet at `willSet` time, so it comes from the
        // parameter.
        cancellable = channel.$verdict
            .sink { [weak self, weak channel] verdict in
                guard let self, let channel else { return }
                apply(verdict, reading: channel.reading, status: channel.status)
            }
        apply(channel.verdict, reading: channel.reading, status: channel.status)
    }

    public func stopConsuming() {
        cancellable = nil
        channel?.stopWatching()
        channel = nil
    }

    /// Turns one verdict into what the strip shows.
    ///
    /// Two mappings here are decisions rather than plumbing. `.unconfirmed` and
    /// `.superseded` both come out as `.watching`: there is a live session and
    /// there is a reading, and the reading is not about what is on screen now,
    /// so the offer is all that may be shown. And `.ended(.userStopped)` is
    /// `.off` rather than an ending — the user stopped it, so there is nothing
    /// to report and nothing to restart. Every other reason keeps its ending,
    /// which is what makes a jetsam kill read as "stopped unexpectedly".
    private func apply(
        _ verdict: CaptureFreshness.Verdict, reading: ScreenReadingRecord?, status: CaptureStatus?
    ) {
        if self.status != status { self.status = status }

        let frames = Int(status?.framesSampled ?? 0)

        switch verdict {
        case .noSession:
            publishAbsence()
        case .starting:
            sessionSeenLive = status?.sessionID
            publish(.starting, from: .capture, frames: frames)
        case .paused:
            sessionSeenLive = status?.sessionID
            publish(.paused, from: .capture, frames: frames)
        case .ended(let reason):
            guard reason != .userStopped, isWorthReporting(status: status) else {
                publishAbsence()
                return
            }
            publish(.ended(reason), from: .capture, frames: frames)
        case .unconfirmed, .superseded:
            sessionSeenLive = status?.sessionID
            publish(.watching, from: .capture, frames: frames)
        case .offerable:
            sessionSeenLive = status?.sessionID
            if let reading {
                publish(.ready(reading.screenContext), from: .capture, frames: frames)
            } else {
                publish(.watching, from: .capture, frames: frames)
            }
        }
    }

    /// The channel has nothing to show: no producer has ever run, the container
    /// is out of reach, the user stopped the session themselves, or the ending on
    /// the page is too old to be news. The scripted demo, if one is running,
    /// keeps the screen — a page left behind by a dead session must not stop a
    /// sample the user just started.
    private func publishAbsence() {
        guard source != .scripted else { return }
        publish(.off, from: .none, frames: 0)
    }

    /// Whether an ending is still news. See `endingWorthShowing`: either this
    /// consumer watched the session run, or it stopped recently enough that the
    /// user still believes it is on.
    private func isWorthReporting(status: CaptureStatus?) -> Bool {
        guard let status else { return false }
        if let sessionSeenLive, sessionSeenLive == status.sessionID { return true }
        return CaptureClock.elapsed(since: status.heartbeatAt) <= Self.endingWorthShowing
    }

    private func publish(_ newState: ScreenContextState, from newSource: Source, frames: Int) {
        // A real session takes the screen off the script rather than racing it.
        if newSource == .capture, task != nil {
            task?.cancel()
            task = nil
        }
        if source != newSource { source = newSource }
        if framesRead != frames { framesRead = frames }
        if newSource == .capture, startedAt == nil { startedAt = Date() }
        if newSource == .none, startedAt != nil { startedAt = nil }
        guard state != newState else { return }
        state = newState
    }

    // MARK: - Reply

    /// The reading Reply may act on, waiting for a fresh one if it has to.
    ///
    /// **It refuses rather than guesses, and that is the whole point of it.**
    /// There is one trigger for a read and it is this tap, so the ordinary case
    /// is that no reading exists yet: the channel gets `intent.readNow` raised
    /// and this waits for a record that answers *that* number and that
    /// `CaptureFreshness` calls offerable. A reading the gate has refused —
    /// superseded by a scrolled or switched conversation, unconfirmed, or older
    /// than the backstop — is never returned, at any point in here. A five
    /// second wait is the honest answer; a reply in the user's own name about
    /// somebody else's message is not.
    ///
    /// The scripted demo short-circuits: its reading is the fiction the
    /// playground is built on and there is no channel to ask.
    public func contextForReply(timeout: Duration = .seconds(12)) async throws -> ScreenContext {
        if source == .scripted, let context = state.context { return context }

        guard let channel else {
            throw AIEngineError.screenNotRead("Screen context is not running.")
        }

        // Freshness is decided at the instant of the tap, never against the last
        // poll, which may be 250 ms old and about the previous conversation.
        channel.poll()
        if channel.verdict == .offerable, let record = channel.reading {
            return record.screenContext
        }

        let sequence = channel.requestRead()
        guard sequence > 0 else {
            throw AIEngineError.screenNotRead(
                "The keyboard cannot reach screen context. It needs Full Access.")
        }

        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(200))
            channel.poll()

            switch channel.verdict {
            case .offerable:
                if let record = channel.reading, record.requestSequence >= sequence {
                    return record.screenContext
                }
            case .ended(let reason):
                throw AIEngineError.screenNotRead(reason.explanation)
            case .noSession:
                throw AIEngineError.screenNotRead("Screen context is not running.")
            case .starting, .paused, .unconfirmed, .superseded:
                continue
            }
        }

        throw AIEngineError.screenNotRead(
            "Screen context did not send back a reading of what is on screen.")
    }

    // MARK: - Frames handed in directly

    /// Hands one captured frame to the reader.
    ///
    /// The in-app path: the containing app holds the frame, so no extension
    /// memory cap applies and `RoutedScreenReader` may keep an English screen on
    /// device. The capture flow does not come through here — its frames never
    /// reach this process, only the text read off them does — which is why this
    /// is the only place `reader` is used.
    public func submit(_ frame: CGImage, appName: String, appIcon: String) async {
        guard let reader, state.isLive else { return }
        framesRead += 1

        do {
            let output = try await reader.read(frame)
            guard let reading = output.value else {
                // A screen with nothing to reply to is a real answer. The strip
                // goes back to watching rather than offering a stale reply.
                if state.context != nil { state = .watching }
                return
            }
            state = .ready(
                ScreenContext(
                    appName: appName,
                    appIcon: appIcon,
                    sender: reading.sender,
                    message: reading.message,
                    language: reading.language))
        } catch {
            // A frame that could not be read is not worth telling the user
            // about: another one arrives in a moment. Only a session that never
            // reads anything is worth surfacing, and that shows as `.watching`.
            state = state.context == nil ? .watching : state
        }
    }

    // MARK: - The scripted demo

    /// The sample timeline the app's playground runs on: start-up, then frames
    /// arriving, then a message worth replying to.
    ///
    /// **This is a demo and the app labels it as one.** Nothing here touches the
    /// capture channel and no screen is read. It yields to a real session the
    /// moment one appears.
    public func start() {
        guard !state.isLive else { return }
        Feedback.actionPress()
        startedAt = Date()
        framesRead = 0
        source = .scripted
        state = .starting

        task?.cancel()
        task = nil

        // A reader is attached, so frames arrive through
        // `submit(_:appName:appIcon:)` and the session waits for them. Running
        // the scripted timeline alongside a real reader would drop the sample
        // context on top of a real reading two seconds in, which is exactly what
        // `ScreenContextBarTests` drives.
        guard reader == nil else {
            state = .watching
            return
        }

        task = Task { @MainActor [weak self] in
            try? await Task.sleep(for: MockScreenContext.startupDelay)
            guard !Task.isCancelled, let self else { return }
            state = .watching

            try? await Task.sleep(for: MockScreenContext.firstReadDelay)
            guard !Task.isCancelled else { return }
            framesRead = 34
            state = .ready(MockScreenContext.sample(at: sampleIndex))

            // Keep the frame counter moving so the session reads as live.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                framesRead += 30
            }
        }
    }

    /// Stops the scripted demo. A real broadcast is stopped by the user, in
    /// Apple's own UI, and nothing in this process can end one — which is why
    /// the strip offers this only while the demo is what is running.
    public func stop() {
        Feedback.modifierPress()
        task?.cancel()
        task = nil
        state = .off
        source = .none
        startedAt = nil
        framesRead = 0
    }

    /// Stands in for the user moving to a different conversation.
    public func advanceToNextSample() {
        guard state.isLive, source == .scripted else { return }
        sampleIndex += 1
        state = .ready(MockScreenContext.sample(at: sampleIndex))
    }
}
