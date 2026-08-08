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

    /// The last Reply tap raised `intent.readNow` and nothing ever answered it.
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
    /// Keying the copy off what actually happened, rather than off a hard-coded
    /// "not built", keeps it true on both sides of that work landing: the first
    /// answered read clears it, and a new broadcast clears it too, because the
    /// last session failing says nothing about this one.
    @Published public private(set) var lastReadWentUnanswered = false

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

    /// Which process this session consumes as. Only the keyboard may raise a
    /// real read; see `contextForReply`.
    private var role: ScreenContextChannel.Role = .keyboard
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

    /// Whether the sample conversation can be played right now.
    ///
    /// False for exactly one reason, and it is a reason the user can act on: a
    /// capture session is watching the screen, and a scripted message painted
    /// over a live one would put a sentence nobody sent where a real one belongs.
    /// The screen that offers the sample renders this as a sentence rather than
    /// as a disabled button with no explanation.
    public var canPlaySample: Bool { !(source == .capture && state.isLive) }

    // MARK: - The real session

    /// Starts consuming a capture channel and publishing what it says.
    ///
    /// The keyboard calls this while it is on screen; the app calls it as an
    /// `.observer`, which reads the same page and never claims the keyboard is
    /// visible. `.observer` does **not** mean "writes nothing": the app renders
    /// the same `KeyboardView` in onboarding and the playground, so a Reply tap
    /// there raises `intent.readNow` like any other. `ScreenContextChannel.Role`
    /// says why that is the contract rather than a hole in it.
    ///
    /// `ownUIHeightFraction` is the keyboard's own geometry, which only the
    /// keyboard can measure and which the producer needs to keep our animating
    /// panel out of the frame fingerprint. `KeyboardGeometry` computes it.
    public func startConsuming(
        _ channel: ScreenContextChannel = .shared,
        as role: ScreenContextChannel.Role = .keyboard,
        ownUIHeightFraction: Double = 0
    ) {
        self.channel = channel
        self.role = role
        channel.startWatching(as: role, ownUIHeightFraction: ownUIHeightFraction)

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

    /// Republishes the keyboard's geometry without restarting the session.
    ///
    /// The height reaches the capture process once, when the keyboard appears,
    /// and a rotation invalidates it: the fraction of the screen we cover changes,
    /// so the band the producer cuts out of the fingerprint changes, so a frame
    /// captured before the rotation and a frame after it have different identities
    /// for no reason the user caused. The freshness gate reads that as a screen
    /// change and retires the reading — a Reply that quietly answers nothing,
    /// because the phone turned while the cloud was thinking.
    ///
    /// Ignored off the keyboard, for the same reason `claimsKeyboardVisible` is:
    /// the app hosts the same view partway up its own screen, and a fraction
    /// measured there describes nothing the capture process should act on.
    public func updateOwnUIHeightFraction(_ fraction: Double) {
        guard role.claimsKeyboardVisible else { return }
        channel?.updateOwnUIHeightFraction(fraction)
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
    /// so the offer is all that may be shown. `.idle` joins them, and that one is
    /// a correction: a frame gap is not a pause, it is a screen that has not
    /// changed *or* a pipeline that has stalled, and rendering it as "paused"
    /// took the Reply button away from a user reading a still conversation on
    /// the strength of a delivery rate nobody has measured. See `frameWindow`.
    ///
    /// **Every ending is reported, including `.stopped`.** It used to map to
    /// `.off`, on the reasoning that the user stopped it on purpose so there was
    /// nothing to say. That reasoning needed the extension to know who stopped
    /// it, and it does not: `broadcastFinished()` carries no reason, so the same
    /// mapping also erased the strip when iOS ended a session for a call or the
    /// lock button — which is the one thing §8.2 forbids. An ending that says
    /// "stopped, restart it in AI Keyboard" after a deliberate stop is
    /// redundant; an ending that says nothing after an involuntary one is wrong.
    private func apply(
        _ verdict: CaptureFreshness.Verdict, reading: ScreenReadingRecord?, status: CaptureStatus?
    ) {
        if self.status != status { self.status = status }

        // A new broadcast is a new chance. Whatever the previous session failed
        // to answer says nothing about this one.
        if let session = status?.sessionID, session != sessionSeenLive {
            lastReadWentUnanswered = false
        }

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
            guard isWorthReporting(status: status) else {
                publishAbsence()
                return
            }
            publish(.ended(reason), from: .capture, frames: frames)
        case .idle, .unconfirmed, .superseded:
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
    /// is out of reach, or the ending on the page is too old to be news.
    /// `publish` is what keeps a running sample on screen through this.
    private func publishAbsence() {
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
        // **A capture session takes the screen from a running sample only while
        // it is actually watching.** The guard used to live in `publishAbsence`
        // alone, which covered `.off` and missed the two states that are far more
        // common on a phone that has ever run a broadcast: a `.paused` session,
        // and an `.ended` one still inside `endingWorthShowing`. Either of those
        // overwrote the sample within one 250 ms poll and cancelled its task, so
        // "Play a sample conversation" looked like a button that did nothing.
        //
        // Live still wins, and that half is not negotiable: a real session is the
        // one with a red dot over it and the fiction must never sit on top of it.
        if source == .scripted, newSource != .scripted, !newState.isLive { return }

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

    // MARK: - The secure-field guard

    /// Whether Reply may ask for a read of a field with these traits, counting
    /// the refusal into the channel when it may not.
    ///
    /// The decision is `SecureField.permitsRead`, which is a pure truth table and
    /// is tested as one. What is here is the half that cannot be pure: the
    /// decision has to leave a number behind, or the open question this guard
    /// rests on — whether any host populates `isSecureTextEntry` through a
    /// `UITextDocumentProxy` at all — stays folklore.
    ///
    /// Both counters move on *every* decision, not only on refusals. Since
    /// silence now permits, a silent host that only counted when it refused would
    /// be indistinguishable from one answering "not secure", and the question
    /// would be unanswerable from the field. `refusedSecureUnknown` standing at
    /// the tap count after a device run is that question answered no.
    @discardableResult
    public func permitsRead(secure: Bool?, contentType: UITextContentType??) -> Bool {
        let permitted = SecureField.permitsRead(secure: secure, contentType: contentType)
        channel?.countSecureDecision(
            refused: !permitted, unanswered: !SecureField.answered(secure: secure))
        return permitted
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

        // The app is an observer: it watches the page so its Screen Context
        // screen can be honest, but it is not the keyboard and its preview is not
        // at the bottom of anyone's screen. A read raised from the in-app
        // playground would photograph *this app* — our own playground, with our
        // own animation inside the fingerprint band — and answer a question
        // nobody asked. The sample is what the playground is for, and it is
        // handled above; anything else is refused rather than read.
        guard role == .keyboard else {
            throw AIEngineError.screenNotRead(
                "Reading the screen works in the keyboard, on the app you are writing in.")
        }

        guard let channel else {
            throw AIEngineError.screenNotRead("Screen context is not running.")
        }

        // Freshness is decided at the instant of the tap, never against the last
        // poll, which may be 250 ms old and about the previous conversation.
        channel.poll()
        if channel.verdict == .offerable, let record = channel.reading {
            lastReadWentUnanswered = false
            return record.screenContext
        }

        let sequence = channel.requestRead()
        guard sequence > 0 else {
            throw AIEngineError.screenNotRead(
                "The keyboard cannot reach screen context. It needs Full Access.")
        }

        // `try`, not `try?`. Swallowing the cancellation here left nothing pacing
        // this loop but the deadline: a cancelled Reply became ~16,000 polls per
        // second, each one a file read, a JSON decode and a SwiftUI invalidation
        // on the main actor, for the rest of the timeout, inside a process capped
        // near 48 MB. Measured at 31,588 polls in 2 s against 6 in the healthy
        // case. And it is the ordinary path rather than an unlucky one: while the
        // capture process runs no reader, every Reply times out, so tapping it
        // again is exactly what a user does. `beginWork` cancels the previous
        // task on every new action, and both of its catch arms already return
        // early on cancellation, so letting this throw is all that is needed.
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(200))
            channel.poll()

            // A read that answered and failed is an answer. Without this the
            // capture process publishes "no backend configured" or "the network
            // went away" and the user still waits out the full timeout, then gets
            // told nothing answered — which is now the wrong reason as well as a
            // slow one. The gate deliberately refuses to call a non-`.read`
            // record offerable, so this has to be asked before the verdict.
            if let record = channel.reading,
                record.requestSequence >= sequence,
                record.outcome != .read
            {
                lastReadWentUnanswered = false
                throw AIEngineError.screenNotRead(record.failureExplanation)
            }

            switch channel.verdict {
            case .offerable:
                if let record = channel.reading, record.requestSequence >= sequence {
                    lastReadWentUnanswered = false
                    return record.screenContext
                }
            case .ended(let reason):
                throw AIEngineError.screenNotRead(reason.explanation)
            case .noSession:
                throw AIEngineError.screenNotRead("Screen context is not running.")
            case .starting, .paused, .idle, .unconfirmed, .superseded:
                continue
            }
        }

        // The reason names what happened rather than a cause it did not check.
        // The old wording — and the sentence `AIEngineError` glued onto it —
        // blamed a stale reading, which is one of five things the gate can
        // refuse and is not the one that happens here: the request was raised,
        // the session stayed alive, and nothing came back.
        lastReadWentUnanswered = true
        throw AIEngineError.screenNotRead(
            "Screen context is watching, but nothing answered the request to read the screen.")
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
    ///
    /// Refused while a capture session is watching, and `canPlaySample` is how
    /// the app says so in words instead of leaving a button that does nothing.
    /// The old guard was `!state.isLive`, which refused for a second reason it
    /// never explained: a paused or recently-ended capture session left `state`
    /// non-live but `source == .capture`, and the sample it did start was then
    /// overwritten by the next poll.
    public func start() {
        guard canPlaySample else { return }
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
