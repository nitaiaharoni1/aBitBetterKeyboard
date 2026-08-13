import Combine
import Foundation
import os

/// The keyboard's end of dictation, polled.
///
/// Ten times a second while the panel is open it reads `DictationState`, keeps
/// the dead-man's switch alive, and looks for a transcript carrying its own
/// utterance number. Nothing here decides anything: the microphone, the gate and
/// the transcriber all live in the containing app, and this reports what they
/// did.
///
/// **Polling rather than a Darwin notification, for the reason
/// `ScreenContextChannel` gives**: a page load ten times a second costs nothing,
/// and a notification path would add a run-loop dependency and a dropped-message
/// failure mode. Faster than screen context's 4 Hz because a microphone button
/// has to feel immediate, and because the level that drives the waveform is read
/// through the same poll.
@MainActor
public final class DictationSession: ObservableObject {

    public static let shared = DictationSession()

    public static let pollInterval: TimeInterval = 0.1

    /// What the keyboard can do about dictation right now. Every case is a
    /// different sentence for the user, which is the reason it is not a boolean
    /// with a spinner.
    public enum Availability: Equatable, Sendable {
        /// No App Group: the keyboard has no Full Access, so it cannot even see
        /// whether a session exists.
        case needsFullAccess
        /// No session is running in the containing app. The ordinary starting
        /// state, and the one that needs the clearest instruction, because
        /// nothing in here can start one.
        case noSession(DictationEndReason)
        /// A session is live and waiting.
        case ready
        case listening
        case transcribing

        public var isLive: Bool {
            switch self {
            case .ready, .listening, .transcribing: return true
            case .needsFullAccess, .noSession: return false
            }
        }
    }

    @Published public private(set) var availability: Availability = .noSession(.notEnded)
    @Published public private(set) var level: Double = 0
    /// Bumped on every poll so the keyboard's waveform keeps a sample even when
    /// loudness has not changed. `@Published` on `level` is Equatable and drops
    /// a held note; three identical bars and a pause is what that looked like.
    @Published public private(set) var levelTick: UInt64 = 0
    @Published public private(set) var transcript = ""
    /// The transcript so far for the utterance this keyboard has open, or
    /// empty when there is none. Replaced wholesale each time a better one
    /// arrives from `poll()` — never appended to, because the app re-sends
    /// the whole utterance on every partial rather than a delta.
    @Published public private(set) var partialTranscript = ""
    /// What the transcriber reported hearing, comma-separated BCP-47, most
    /// spoken first. Empty until a transcript lands.
    @Published public private(set) var transcriptLanguages = ""
    @Published public private(set) var failure = ""
    /// Seconds before the session closes itself, when it will.
    @Published public private(set) var remainingSeconds: Double?

    /// The utterance this keyboard opened. A transcript carrying any other
    /// number answers a tap the user has already moved past.
    public private(set) var utterance: UInt64 = 0

    /// The user has tapped Insert and the words have not arrived.
    ///
    /// **Without this the panel said "Transcribing" for the first tenth of a
    /// second of every recording.** The recorder publishes its phase on its own
    /// 10 Hz poll, so between the keyboard opening an utterance and the recorder
    /// noticing, the page still reads `idle` — and an open utterance over an idle
    /// page is genuinely ambiguous between "not started yet" and "finished, words
    /// in flight". Only this side knows which, because only this side was
    /// tapped.
    private var awaitingTranscript = false

    private var reader: DictationChannelReader?
    private var timer: Timer?
    /// The highest partial sequence already applied to `partialTranscript`,
    /// scoped to the utterance currently open — reset everywhere `utterance`
    /// or `partialTranscript` is reset, so a fresh utterance's first partial
    /// is never compared against the previous utterance's last one.
    private var lastAppliedPartialSequence: UInt32 = 0
    private var lastLogged = ""
    /// The loudest level seen since the last line was emitted. See `report()`.
    private var peakSinceLogged: Double = 0

    private static let log = Logger(subsystem: "com.nitai.aikeyboard", category: "Dictation")

    /// A reader passed here roots the channel somewhere other than the App
    /// Group, which is how `AIKeyboardCoreTests` drives both ends without an
    /// entitlement.
    public init(reader: DictationChannelReader? = nil) {
        self.reader = reader
    }

    public var isReachable: Bool { DictationChannel.isReachable }

    // MARK: Watching

    /// Reads the channel once, without starting the poll.
    ///
    /// **Anything that decides something on `availability` has to call this
    /// first, and for the whole of this feature's life the microphone key did
    /// not.** `availability` is a cache with one writer — `poll()` — and it only
    /// tracks the page while the timer below is running. `startWatching()` used
    /// to be reached *after* `startDictation`'s availability check, so the check
    /// read the `.noSession(.notEnded)` this class is initialised with, refused,
    /// and returned before starting the poll that would have corrected it. Every
    /// tap refused, on a phone where a session was live, forever. Creating the
    /// reader is part of the job and not an optimisation to skip: it is failable,
    /// nil means the App Group is out of reach, and that is the whole of
    /// `.needsFullAccess` — so polling without it reports a Full Access problem
    /// the user does not have.
    public func refresh() {
        if reader == nil { reader = DictationChannelReader() }
        // The same obligation the capture channel has: a transcript whose
        // session is gone is a sentence somebody dictated, sitting in a
        // container that is backed up.
        reader?.discardTranscriptOfADeadSession()
        poll()
    }

    public func startWatching() {
        guard timer == nil else { return }
        refresh()

        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// **Forgets what the last poll saw, and that is the other half of the same
    /// bug.** The banner reads `availability` whether or not anything is
    /// refreshing it, so the `.ready` left behind here — by the transcript sink,
    /// which stops the watch the moment the words are inserted — went on reading
    /// as a live session. `BannerState.resolve` kept the dictation strip up over
    /// a sentence already in the document, and the next tap on the microphone
    /// passed a guard describing a session that could have been gone for an hour:
    /// `beginUtterance` answers a number whether or not a recorder exists, so the
    /// keyboard showed Listening and waited for a transcript nothing would ever
    /// publish. Not watching means knowing of no session. That is the safe
    /// direction — the cost of being wrong is a refusal the next `refresh()`
    /// overturns in the same tap.
    public func stopWatching() {
        timer?.invalidate()
        timer = nil
        lastLogged = ""
        availability = .noSession(.notEnded)
        level = 0
        remainingSeconds = nil
        partialTranscript = ""
        lastAppliedPartialSequence = 0
    }

    // MARK: Utterances

    /// Opens an utterance. Returns false when there is no live session to open
    /// one in, which the panel shows rather than spinning.
    @discardableResult
    public func beginUtterance() -> Bool {
        guard let reader, availability.isLive else { return false }
        transcript = ""
        transcriptLanguages = ""
        failure = ""
        partialTranscript = ""
        lastAppliedPartialSequence = 0
        awaitingTranscript = false
        utterance = reader.beginUtterance()
        poll()
        return utterance > 0
    }

    public func stopUtterance() {
        awaitingTranscript = true
        reader?.stopUtterance()
        poll()
    }

    public func cancelUtterance() {
        reader?.cancelUtterance()
        utterance = 0
        awaitingTranscript = false
        transcript = ""
        transcriptLanguages = ""
        failure = ""
        partialTranscript = ""
        lastAppliedPartialSequence = 0
        poll()
    }

    // MARK: The poll

    func poll() {
        // **No reader is the whole of `.needsFullAccess`, and nothing else is.**
        // `DictationChannelReader()` answers nil exactly when the App Group
        // container is out of reach, which in the keyboard means Full Access has
        // not been granted. An earlier version also asked whether `state()` was
        // nil, which conflates "I cannot see the channel" with "nobody has
        // started a session" — two different sentences for the user, and the
        // second one is by far the more common.
        guard let reader else {
            availability = .needsFullAccess
            return
        }

        let now = CaptureClock.now()
        // Refreshed on every poll, including while idle: it is what tells the
        // recorder this keyboard still exists, and a keyboard that is killed
        // rather than dismissed stops refreshing it within the window.
        reader.keepAlive(now: now)

        guard let state = reader.state(), state.isAlive(now: now) else {
            let reason = reader.state()?.endReason ?? .notEnded
            // A session whose heartbeat stopped without an ending written is
            // `.lost`, and that is a reader's conclusion rather than anything
            // the page says — see `DictationState.heartbeatAt`.
            let ended: DictationEndReason =
                (reader.state()?.sessionID != nil && reason == .notEnded) ? .lost : reason
            availability = .noSession(ended)
            level = 0
            remainingSeconds = nil
            levelTick &+= 1
            report()
            return
        }

        remainingSeconds = state.remainingSeconds(now: now)
        level = state.level
        levelTick &+= 1

        switch state.phase {
        case .idle:
            availability =
                utterance > 0 ? (awaitingTranscript ? .transcribing : .listening) : .ready
        case .listening: availability = .listening
        case .transcribing: availability = .transcribing
        }

        // **Cheapest check first.** `state.partialSequence` is a plain integer
        // read off the page already in hand, so comparing it against the last
        // one applied costs nothing; `reader.partial()` opens and decodes a
        // file, which is worth doing only once there is reason to think it
        // changed. The record itself is still checked against this keyboard's
        // own session and utterance — the page can say "something changed"
        // for a partial that belongs to nobody this keyboard is listening to.
        if utterance > 0, state.partialSequence != lastAppliedPartialSequence,
            let partial = reader.partial(), partial.sessionID == state.sessionID,
            partial.utterance == utterance, partial.sequence > lastAppliedPartialSequence
        {
            lastAppliedPartialSequence = partial.sequence
            partialTranscript = partial.text
        }

        if utterance > 0, let record = reader.transcript(), record.utterance == utterance,
            record.sessionID == state.sessionID
        {
            utterance = 0
            awaitingTranscript = false
            availability = .ready
            level = 0
            partialTranscript = ""
            switch record.outcome {
            case .transcribed:
                transcriptLanguages = record.languages
                transcript = record.text
                failure = ""
            case .nothing, .failed:
                transcript = ""
                failure = record.failureExplanation
            }
        }
        report()
    }

    /// One line per change of what this process can see, emitted by the
    /// *consuming* process — a process always sees its own writes, so a log from
    /// the recorder would prove nothing about the two sharing a page.
    /// `Scripts/prove-dictation.sh` greps for this prefix.
    private func report() {
        peakSinceLogged = max(peakSinceLogged, level)

        // **The level is deliberately not part of what "changed" means.** It
        // moves on every poll while somebody is speaking, so including it in the
        // comparison turned this into ten log lines a second from a keyboard
        // extension — which is both waste and a way to lose the lines that
        // matter. What is logged is the peak since the last line, so the level
        // still crosses into the log without deciding when to write one.
        // **The partial is in the line for the same reason the transcript is.**
        // Streaming crosses the App Group exactly as the final transcript does, and
        // the only evidence that it does is what the *consuming* process says it
        // saw — a log from the recorder would prove nothing about the two sharing a
        // page. Without this, `Scripts/prove-dictation.sh` could prove that a
        // transcript crosses and nothing at all about the readings before it.
        let line =
            "dictation-watch storage=\(DictationChannel.isReachable ? "appGroup" : "processLocal") "
            + "availability=\(Self.name(of: availability)) utterance=\(utterance) "
            + "partial=\(partialTranscript.isEmpty ? "none" : String(partialTranscript.prefix(24))) "
            + "transcript=\(transcript.isEmpty ? "none" : String(transcript.prefix(24)))"
        guard line != lastLogged else { return }
        lastLogged = line
        let peak = Int(peakSinceLogged * 100)
        peakSinceLogged = 0
        Self.log.notice("\(line, privacy: .public) peakLevel=\(peak, privacy: .public)")
    }

    private static func name(of availability: Availability) -> String {
        switch availability {
        case .needsFullAccess: return "needsFullAccess"
        case .noSession(let reason): return "noSession:\(reason)"
        case .ready: return "ready"
        case .listening: return "listening"
        case .transcribing: return "transcribing"
        }
    }
}
