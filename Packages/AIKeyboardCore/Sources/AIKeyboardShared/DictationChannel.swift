import Foundation
import os

// MARK: - Why there is a channel here at all
//
// **The keyboard cannot record, and that is an OS boundary, not a permission.**
// Apple's "Configuring open access for a custom keyboard" lists "No access to
// microphone and speaker" under the keyboard sandbox, and enabling open access
// adds Location, Contacts, a shared container, network and iCloud — never the
// microphone. Developers who try it anyway get `AVAudioSession` error 561145187,
// `cannotStartRecording`, with Full Access granted and the microphone entitled.
//
// **So the microphone lives in the containing app, and this is the wire between
// them.** That is the architecture Wispr Flow ships on iOS — a "Flow Session"
// held open by their app while their keyboard is a reader — and it is the one
// this repo already runs for screen context: sensor in another process, result
// across the App Group, keyboard reads and never decides.
//
// **The session has to be started from the app, in the foreground, and that is
// the same 561145187.** An app in the background cannot *begin* recording; an
// app whose recording session is already active keeps it across a switch under
// the `audio` background mode. So the shape is forced: the user starts a session
// in AI Keyboard, switches to WhatsApp, and the keyboard's microphone button
// then opens and closes utterances inside a session that is already live. There
// is no supported way for a keyboard extension to launch its own app —
// `UIApplication` is unavailable to extensions and the responder-chain `openURL`
// workaround is explicitly disallowed — so nothing here pretends to have one.
// When no session is live the keyboard says so and says where to go.
//
// **Nothing in this channel is audio.** The recording lives in one buffer in the
// app, goes to the transcriber, and is released; what crosses is text, levels
// and counters. `ScreenReadingRecord` carries the same promise for pixels, and
// for the same reason: the shared container is backed up.

// MARK: - Where the channel lives

public enum DictationChannel {

    public static let statePageBytes = 192
    public static let requestPageBytes = 96

    public static var directoryURL: URL? {
        SharedContainer.url?.appendingPathComponent("dictation", isDirectory: true)
    }

    public static var stateURL: URL? { directoryURL?.appendingPathComponent("state.bin") }
    public static var requestURL: URL? { directoryURL?.appendingPathComponent("request.bin") }
    public static var transcriptURL: URL? {
        directoryURL?.appendingPathComponent("transcript.json")
    }

    /// False in the keyboard until the user grants Full Access, which is why
    /// dictation is a Full-Access feature end to end.
    public static var isReachable: Bool { SharedContainer.url != nil }

    static let log = Logger(subsystem: "com.nitai.aikeyboard", category: "DictationChannel")

    /// Zeroed in place rather than unlinked, for the reason `CaptureChannel.clear()`
    /// gives: another process may have these pages mapped, and unlinking a mapped
    /// file leaves it reading an inode nobody will write again.
    public static func clear() {
        guard prepareDirectory() != nil, let stateURL, let requestURL, let transcriptURL else {
            return
        }
        SharedPage<DictationState>(url: stateURL, bytes: statePageBytes, writable: true)?.reset()
        SharedPage<DictationRequest>(url: requestURL, bytes: requestPageBytes, writable: true)?
            .reset()
        try? FileManager.default.removeItem(at: transcriptURL)
    }

    /// Removes a transcript whose session is no longer running.
    ///
    /// The same obligation `CaptureChannel.discardReadingOfADeadSession` carries,
    /// and it is sharper here: a transcript is a sentence the user *dictated*,
    /// sitting in a container that is backed up. The app deletes it when a
    /// session ends; this covers the ending the app never sees, which is the
    /// jetsam kill the whole heartbeat exists to detect.
    @discardableResult
    public static func discardTranscriptOfADeadSession(
        in directory: URL, now: UInt64 = CaptureClock.now()
    ) -> Bool {
        let transcript = directory.appendingPathComponent("transcript.json")
        guard FileManager.default.fileExists(atPath: transcript.path) else { return false }

        let state = SharedPage<DictationState>(
            url: directory.appendingPathComponent("state.bin"),
            bytes: statePageBytes, writable: false)?.load()
        if let state, state.isAlive(now: now) { return false }

        return (try? FileManager.default.removeItem(at: transcript)) != nil
    }

    static func prepareDirectory(_ url: URL? = DictationChannel.directoryURL) -> URL? {
        guard let url else { return nil }
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}

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
        case .microphoneDenied: return "AI Keyboard doesn't have microphone access."
        case .audioFailed: return "The microphone stopped working."
        case .lost: return "The AI Keyboard app stopped running in the background."
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

    public init() {}

    /// Three seconds, the same window the state's heartbeat uses.
    public static let keyboardWindow = CaptureClock.nanoseconds(3)

    public func isKeyboardAlive(now: UInt64 = CaptureClock.now()) -> Bool {
        CaptureClock.elapsed(since: keyboardAliveAt, now: now) <= Self.keyboardWindow
    }

    /// Whether the recorder should be capturing right now.
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

// MARK: - The recording end

/// The app's end: it owns `state.bin`, reads `request.bin`, and is the only
/// thing that ever writes a transcript.
public final class DictationChannelWriter: @unchecked Sendable {

    private let statePage: SharedPage<DictationState>
    private let requestURL: URL
    private let transcriptURL: URL
    private let requestPage = OSAllocatedUnfairLock<SharedPage<DictationRequest>?>(initialState: nil)
    private let hasEnded = OSAllocatedUnfairLock(initialState: false)

    public convenience init?() {
        guard let directory = DictationChannel.prepareDirectory() else { return nil }
        self.init(directory: directory)
    }

    /// Public for the reason `CaptureChannelWriter.init(directory:)` is:
    /// `AIKeyboardCoreTests` carries no App Group entitlement, so both ends are
    /// driven against a temporary directory there.
    public init?(directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard
            let page = SharedPage<DictationState>(
                url: directory.appendingPathComponent("state.bin"),
                bytes: DictationChannel.statePageBytes, writable: true)
        else { return nil }
        self.statePage = page
        self.requestURL = directory.appendingPathComponent("request.bin")
        self.transcriptURL = directory.appendingPathComponent("transcript.json")
    }

    @discardableResult
    public func begin(
        sessionID: UUID = UUID(), seconds: Double, microphoneAuthorized: Bool,
        now: UInt64 = CaptureClock.now()
    ) -> UUID {
        hasEnded.withLock { $0 = false }
        try? FileManager.default.removeItem(at: transcriptURL)
        statePage.reset()
        statePage.mutate { state in
            state.setSessionID(sessionID)
            state.startedAt = now
            state.heartbeatAt = now
            state.expiresAt = seconds > 0 ? now &+ CaptureClock.nanoseconds(seconds) : 0
            state.micAuthorizedRaw = microphoneAuthorized ? 1 : 0
            state.phaseRaw = DictationPhase.idle.rawValue
            state.endReasonRaw = DictationEndReason.notEnded.rawValue
        }
        return sessionID
    }

    public func heartbeat(now: UInt64 = CaptureClock.now()) {
        statePage.mutate { $0.heartbeatAt = now }
    }

    public func setPhase(_ phase: DictationPhase, utterance: UInt64 = 0) {
        statePage.mutate { state in
            state.phaseRaw = phase.rawValue
            if utterance > 0 { state.currentUtterance = utterance }
        }
    }

    /// Written from the audio tap, so it does exactly one seqlock write and
    /// returns. Nothing here allocates.
    public func setLevel(_ level: Double) {
        statePage.mutate { $0.setLevel(level) }
    }

    public func count(_ counter: WritableKeyPath<DictationState, UInt32>) {
        statePage.mutate { $0[keyPath: counter] &+= 1 }
    }

    public func end(_ reason: DictationEndReason, now: UInt64 = CaptureClock.now()) {
        hasEnded.withLock { $0 = true }
        statePage.mutate { state in
            state.endReasonRaw = reason.rawValue
            state.phaseRaw = DictationPhase.idle.rawValue
            state.levelPermille = 0
            state.heartbeatAt = now
        }
        try? FileManager.default.removeItem(at: transcriptURL)
    }

    public func state() -> DictationState? { statePage.load() }

    public func request() -> DictationRequest? {
        requestPage.withLock { page in
            if page == nil {
                page = SharedPage<DictationRequest>(
                    url: requestURL, bytes: DictationChannel.requestPageBytes, writable: false)
            }
            return page?.load()
        }
    }

    /// Publishes a transcript, atomically so the keyboard never reads half a JSON
    /// document.
    ///
    /// **Refused once the session has ended, and it deletes again afterwards** —
    /// the same two-sided check `CaptureChannelWriter.publish` makes, for the
    /// same reason: a transcription in flight when the user stopped the session
    /// lands after `end()` deleted the file, and a sentence somebody dictated
    /// would then sit in a backed-up container until the next launch.
    public func publish(_ record: DictationTranscriptRecord) throws {
        guard !hasEnded.withLock({ $0 }) else { throw DictationChannelError.sessionEnded }

        let data = try JSONEncoder().encode(record)
        try data.write(
            to: transcriptURL,
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        statePage.mutate { $0.completedUtterance = record.utterance }

        if hasEnded.withLock({ $0 }) {
            try? FileManager.default.removeItem(at: transcriptURL)
            throw DictationChannelError.sessionEnded
        }
    }
}

public enum DictationChannelError: Error, LocalizedError {
    case sessionEnded

    public var errorDescription: String? {
        "the dictation session ended before the transcript could be published"
    }
}

// MARK: - The keyboard end

/// The keyboard's end: it reads `state.bin` and the transcript, and owns
/// `request.bin`.
public final class DictationChannelReader: @unchecked Sendable {

    private let stateURL: URL
    private let transcriptURL: URL
    private let directory: URL
    private let requestPage: SharedPage<DictationRequest>?
    private let statePage = OSAllocatedUnfairLock<SharedPage<DictationState>?>(initialState: nil)

    public convenience init?() {
        guard let directory = DictationChannel.prepareDirectory() else { return nil }
        self.init(directory: directory)
    }

    public init(directory: URL) {
        self.directory = directory
        self.stateURL = directory.appendingPathComponent("state.bin")
        self.transcriptURL = directory.appendingPathComponent("transcript.json")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.requestPage = SharedPage<DictationRequest>(
            url: directory.appendingPathComponent("request.bin"),
            bytes: DictationChannel.requestPageBytes, writable: true)
    }

    public func state() -> DictationState? {
        statePage.withLock { page in
            if page == nil {
                page = SharedPage<DictationState>(
                    url: stateURL, bytes: DictationChannel.statePageBytes, writable: false)
            }
            return page?.load()
        }
    }

    public func transcript() -> DictationTranscriptRecord? {
        guard let data = try? Data(contentsOf: transcriptURL) else { return nil }
        return try? JSONDecoder().decode(DictationTranscriptRecord.self, from: data)
    }

    @discardableResult
    public func discardTranscriptOfADeadSession(now: UInt64 = CaptureClock.now()) -> Bool {
        DictationChannel.discardTranscriptOfADeadSession(in: directory, now: now)
    }

    /// The dead-man's switch, refreshed on every poll while the panel is open.
    public func keepAlive(now: UInt64 = CaptureClock.now()) {
        requestPage?.mutate { $0.keyboardAliveAt = now }
    }

    /// Opens an utterance and returns its number. The transcript that answers
    /// this tap carries the number this returns; anything else answers an
    /// earlier one.
    @discardableResult
    public func beginUtterance(now: UInt64 = CaptureClock.now()) -> UInt64 {
        guard let requestPage else { return 0 }
        var opened: UInt64 = 0
        requestPage.mutate { request in
            request.utterance &+= 1
            request.startedAt = now
            request.keyboardAliveAt = now
            opened = request.utterance
        }
        return opened
    }

    public func stopUtterance(now: UInt64 = CaptureClock.now()) {
        requestPage?.mutate { request in
            request.stopUtterance = request.utterance
            request.stoppedAt = now
            request.keyboardAliveAt = now
        }
    }

    public func cancelUtterance(now: UInt64 = CaptureClock.now()) {
        requestPage?.mutate { request in
            request.cancelUtterance = request.utterance
            request.cancelledAt = now
            request.keyboardAliveAt = now
        }
    }

    public func request() -> DictationRequest? { requestPage?.load() }
}
