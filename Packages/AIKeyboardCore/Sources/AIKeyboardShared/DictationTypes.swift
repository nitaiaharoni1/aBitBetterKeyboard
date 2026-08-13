import Foundation

// MARK: - State

/// What the recording process publishes about itself.
///
/// Fixed layout, plain integers, no references and no optionals, for the reason
/// `CaptureStatus` gives: the bytes are memcpy'd through a shared page and read
/// by a process that may see them mid-write, so every bit pattern has to be a
/// value rather than a crash.
public struct DictationState: Equatable, Sendable {

    public var sessionHigh: UInt64 = 0
    public var sessionLow: UInt64 = 0

    /// `CaptureClock` nanoseconds, all of them.
    public var startedAt: UInt64 = 0

    /// Written once a second by the recording session and by nothing else.
    ///
    /// **The single most load-bearing field in this page.** Every other liveness
    /// signal here can be left behind by a process that no longer exists: iOS
    /// jetsams a backgrounded app without running any of its code, so `phase`
    /// stays `listening` and `expiresAt` stays in the future while the microphone
    /// has in fact been gone for a minute. A heartbeat that has stopped is the
    /// only thing that says so, which is why `isAlive` asks this and not `phase`.
    public var heartbeatAt: UInt64 = 0

    /// When the session stops on its own. A recording session with no end is a
    /// microphone the user forgot they left on.
    public var expiresAt: UInt64 = 0

    /// The utterance the recorder is working on, matching `DictationRequest.utterance`.
    public var currentUtterance: UInt64 = 0
    /// The most recent utterance whose transcript has been published.
    public var completedUtterance: UInt64 = 0

    /// Peak level of the last frame, in per mille. Feeds the waveform; gates
    /// nothing. Per mille as an integer for the reason `ownUIHeightPermille` is:
    /// every bit pattern in this page has to be a value, and a `Double` here can
    /// be a NaN read mid-write.
    public var levelPermille: UInt16 = 0

    public var phaseRaw: UInt8 = DictationPhase.idle.rawValue
    public var endReasonRaw: UInt8 = DictationEndReason.notEnded.rawValue
    public var micAuthorizedRaw: UInt8 = 0
    private var padding0: UInt8 = 0
    private var padding1: UInt16 = 0

    // MARK: Counters
    public var utterances: UInt32 = 0
    /// Utterances the on-device `SpeechGate` refused before any upload. Worth a
    /// counter of its own: it is the number that says how often the thing that
    /// would otherwise have invented a sentence was stopped.
    public var refusedNoSpeech: UInt32 = 0
    public var failures: UInt32 = 0
    /// Bumped by `DictationChannelWriter.publishPartial` every time a fresher
    /// partial transcript is written. The keyboard polls this at 10 Hz and
    /// only reads `partial.json` when the number has moved — a plain integer
    /// is cheap enough to compare on every tick, and the file it stands in
    /// for is not.
    public var partialSequence: UInt32 = 0

    public init() {}

    public var sessionID: UUID? {
        guard sessionHigh != 0 || sessionLow != 0 else { return nil }
        return UUID(high: sessionHigh, low: sessionLow)
    }

    public mutating func setSessionID(_ id: UUID) {
        (sessionHigh, sessionLow) = id.words
    }

    public var phase: DictationPhase { DictationPhase(rawValue: phaseRaw) ?? .idle }

    /// An ending this build does not recognise reads as `.lost`, never as "no
    /// ending": reporting no ending for an ending that happened is the one
    /// direction that renders as a working session the user cannot use.
    public var endReason: DictationEndReason {
        DictationEndReason(rawValue: endReasonRaw) ?? .lost
    }

    public var isMicrophoneAuthorized: Bool { micAuthorizedRaw != 0 }

    public var level: Double { Double(levelPermille) / 1000 }

    public mutating func setLevel(_ level: Double) {
        guard level.isFinite, level > 0 else {
            levelPermille = 0
            return
        }
        levelPermille = UInt16(min(1000, (level * 1000).rounded()))
    }

    /// Three seconds of a one-second heartbeat. Two may be missed to a busy main
    /// thread; three have not been missed, the process is gone.
    public static let heartbeatWindow = CaptureClock.nanoseconds(3)

    /// Whether a recording session is running *right now* — the only question
    /// the keyboard may act on.
    public func isAlive(now: UInt64 = CaptureClock.now()) -> Bool {
        guard sessionID != nil, endReason == .notEnded else { return false }
        guard CaptureClock.elapsed(since: heartbeatAt, now: now) <= Self.heartbeatWindow else {
            return false
        }
        return expiresAt == 0 || now < expiresAt
    }

    /// Seconds left before the session expires, nil when it does not.
    public func remainingSeconds(now: UInt64 = CaptureClock.now()) -> Double? {
        guard expiresAt > now else { return expiresAt == 0 ? nil : 0 }
        return Double(expiresAt - now) / 1_000_000_000
    }
}

public enum DictationPhase: UInt8, Sendable {
    /// A session is running and the microphone is open, but nothing is being
    /// kept. Between utterances.
    case idle = 0
    /// Recording an utterance the keyboard asked for.
    case listening = 1
    /// The recording is closed and the transcriber has it.
    case transcribing = 2
}

/// Why a session is not running. Every case is a different thing for the user to
/// do, which is the whole reason this is not a boolean.
public enum DictationEndReason: UInt8, Sendable, Equatable {
    case notEnded = 0
    case stoppedByUser = 1
    /// A phone call, Siri, or another app taking the microphone.
    case interrupted = 2
    /// The session ran its length. Not a failure — the point of a session having
    /// one is that a microphone nobody remembered closes itself.
    case expired = 3
    /// Microphone permission was refused or revoked.
    case microphoneDenied = 4
    /// The audio engine stopped and could not be restarted.
    case audioFailed = 5
    /// The heartbeat stopped without an ending being written: the app was
    /// jetsammed, force-quit, or crashed. Nothing writes this — it is what a
    /// *reader* concludes, which is why `isAlive` asks the heartbeat.
    case lost = 6

    public var explanation: String {
        switch self {
        case .notEnded: return ""
        case .stoppedByUser: return "Dictation is off."
        case .interrupted: return "Something else took the microphone."
        case .expired: return "The dictation session timed out."
        case .microphoneDenied: return "aBitBetterKeyboard doesn't have microphone access."
        case .audioFailed: return "The microphone stopped working."
        case .lost: return "The aBitBetterKeyboard app stopped running in the background."
        }
    }
}

// MARK: - Request

/// What the keyboard asks of the recorder. Deliberately tiny: the keyboard can
/// open and close an utterance inside a session somebody else started, and
/// nothing else.
public struct DictationRequest: Equatable, Sendable {

    /// Raised when the user starts speaking. Monotonic, so a transcript can be
    /// matched to the tap that asked for it rather than to the previous one.
    public var utterance: UInt64 = 0
    public var startedAt: UInt64 = 0

    /// Set equal to `utterance` when the user stops. The recorder closes the
    /// recording and transcribes it.
    public var stopUtterance: UInt64 = 0
    public var stoppedAt: UInt64 = 0

    /// Set equal to `utterance` when the user cancels. The recording is dropped
    /// without being sent anywhere.
    public var cancelUtterance: UInt64 = 0
    public var cancelledAt: UInt64 = 0

    /// **A dead-man's switch, and it is a privacy control rather than a nicety.**
    /// A keyboard extension is killed rather than dismissed all the time, and
    /// without this the recorder would keep an utterance open — microphone live,
    /// audio accumulating — for nobody. The recorder abandons any open recording
    /// whose keyboard has stopped writing this.
    public var keyboardAliveAt: UInt64 = 0

    /// **Kept as explicit padding rather than removed**, because this struct is
    /// memcpy'd through a fixed-size shared page and its layout is the wire
    /// format two processes agree on. It held `pausedRaw` until pause was taken
    /// out of the product; leaving the bytes where they were means the page keeps
    /// the same shape and every field after it keeps the same offset.
    private var padding0: UInt32 = 0
    private var padding1: UInt32 = 0

    public init() {}

    /// Three seconds, the same window the state's heartbeat uses.
    public static let keyboardWindow = CaptureClock.nanoseconds(3)

    public func isKeyboardAlive(now: UInt64 = CaptureClock.now()) -> Bool {
        CaptureClock.elapsed(since: keyboardAliveAt, now: now) <= Self.keyboardWindow
    }

    /// Whether the recorder should be capturing right now.
    ///
    public func wantsRecording(now: UInt64 = CaptureClock.now()) -> Bool {
        guard utterance > 0, isKeyboardAlive(now: now) else { return false }
        return stopUtterance < utterance && cancelUtterance < utterance
    }
}

// MARK: - Transcript

public enum DictationOutcome: String, Codable, Sendable {
    case transcribed
    /// The recording had no speech in it. An answer, not a failure — and the one
    /// `SpeechGate` produces without a network call.
    case nothing
    case failed
}

/// One utterance, as it crosses the App Group.
///
/// **Text only, by construction.** No audio, no file name, no path to one. The
/// recording exists as bytes in the recorder's memory for as long as the upload
/// takes and is then released, so nothing on disk, in this container or in a
/// backup is ever a recording of the user. Adding a field here that could be
/// turned back into sound breaks that sentence, so do not.
public struct DictationTranscriptRecord: Codable, Equatable, Sendable {

    public let sessionID: UUID
    /// The `DictationRequest.utterance` this answers. A transcript carrying an
    /// earlier number is the answer to a tap the user has already moved past.
    public let utterance: UInt64

    public let outcome: DictationOutcome
    public let text: String
    /// BCP-47 codes the transcriber heard, most-spoken first, comma-separated.
    /// A string rather than an array for the reason `ScreenReadingRecord.language`
    /// is one: this is a file format two processes parse, and an unfamiliar value
    /// must widen a default rather than fail the decode of the text beside it.
    public let languages: String
    /// Why there is no text, in a sentence fit to show. Empty when transcribed.
    public let detail: String

    /// `AIProvenance` raw form. Always `cloud` today — Apple's on-device stack
    /// has no Hebrew — but the field is here so an on-device transcriber can be
    /// told apart from a cloud one the day one exists.
    public let provenance: String

    /// `CaptureClock` nanoseconds.
    public let recordedAt: UInt64
    public let completedAt: UInt64
    /// How long the recording was.
    public let seconds: Double

    public init(
        sessionID: UUID,
        utterance: UInt64,
        outcome: DictationOutcome = .transcribed,
        text: String,
        languages: String = "",
        detail: String = "",
        provenance: String = "cloud",
        recordedAt: UInt64,
        completedAt: UInt64,
        seconds: Double
    ) {
        self.sessionID = sessionID
        self.utterance = utterance
        self.outcome = outcome
        self.text = text
        self.languages = languages
        self.detail = detail
        self.provenance = provenance
        self.recordedAt = recordedAt
        self.completedAt = completedAt
        self.seconds = seconds
    }

    public var failureExplanation: String {
        switch outcome {
        case .transcribed: return ""
        case .nothing: return detail.isEmpty ? "I didn't catch that." : detail
        case .failed: return detail.isEmpty ? "That couldn't be transcribed." : detail
        }
    }
}

/// What the utterance the keyboard has open sounds like so far, republished
/// as the recording continues rather than sent once at the end.
///
/// **Text only, by construction — the same promise `DictationTranscriptRecord`
/// carries and for the same reason.** A partial is still a sentence somebody
/// is in the middle of saying; nothing here is audio, and nothing here is a
/// path to any.
public struct DictationPartialRecord: Codable, Equatable, Sendable {

    public let sessionID: UUID
    /// The `DictationRequest.utterance` this answers. A partial carrying any
    /// other number belongs to an utterance the keyboard has already moved
    /// past.
    public let utterance: UInt64
    /// Rises by one every time this utterance gets a fresher partial.
    /// `DictationState.partialSequence` carries the same number, which is how
    /// the keyboard notices there is something new without parsing this file,
    /// and a reader that has already applied a higher number than this one
    /// ignores it — a partial must never make the text on screen go backwards.
    public let sequence: UInt32
    public let text: String
    /// BCP-47 codes, same shape as `DictationTranscriptRecord.languages`.
    public let languages: String
    /// How much audio this partial was taken from.
    public let seconds: Double

    public init(
        sessionID: UUID, utterance: UInt64, sequence: UInt32, text: String, languages: String = "",
        seconds: Double
    ) {
        self.sessionID = sessionID
        self.utterance = utterance
        self.sequence = sequence
        self.text = text
        self.languages = languages
        self.seconds = seconds
    }
}
