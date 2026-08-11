import AIKeyboardCore
import AVFoundation
import Combine
import Foundation
import os

/// Holds the microphone for the keyboard, because the keyboard cannot.
///
/// **The whole design is forced by one error code.** A keyboard extension that
/// calls `AVAudioSession.setActive(true)` for recording gets 561145187,
/// `cannotStartRecording`, with Full Access granted and the microphone entitled —
/// Apple's custom-keyboard guidance lists "No access to microphone and speaker"
/// under the keyboard sandbox and open access adds Location, Contacts, a shared
/// container, network and iCloud, never the microphone. So the microphone lives
/// here, in the containing app, and the keyboard reads a transcript across the
/// App Group. That is what Wispr Flow ships on iOS and it is the shape this repo
/// already runs for screen context.
///
/// **The same error code is why there is a session at all rather than a button.**
/// An app in the background cannot *begin* recording; an app whose recording
/// session is already active keeps it across a switch, under the `audio`
/// background mode. So the user starts a session here, in the foreground, and
/// the keyboard then opens and closes utterances inside a session that is
/// already live. When no session is running, the keyboard's "Open AI Keyboard"
/// banner button asks the extension host to open this app via
/// `extensionContext?.open(_:)`, and `DictationHandoffView` starts the session
/// automatically on arrival.
///
/// **What has actually run.** The channel, the gate, the encoder and the
/// transcription are exercised by tests and by `Bar/dictation/`. The
/// `AVAudioEngine` half below has not been run on a device by anyone, and a
/// simulator cannot settle it: background audio, jetsam and interruption are
/// device behaviours. `Scripts/prove-dictation.sh` is what turns that into a
/// measurement when a phone is available.
@MainActor
public final class DictationService: ObservableObject {

    public static let shared = DictationService()

    // MARK: Published state

    @Published public internal(set) var isRunning = false
    @Published public internal(set) var phase: DictationPhase = .idle
    @Published public internal(set) var level: Double = 0
    @Published public internal(set) var lastTranscript = ""
    @Published public internal(set) var lastError = ""
    @Published public internal(set) var utterances = 0
    @Published public internal(set) var refusedNoSpeech = 0
    @Published public internal(set) var endReason: DictationEndReason = .notEnded
    @Published public internal(set) var expiresAt: Date?

    // MARK: Machinery

    let engine = AVAudioEngine()
    var writer: DictationChannelWriter?
    /// Shared with the audio thread. See `LiveRecording`.
    let recording = LiveRecording()
    var openUtterance: UInt64 = 0
    var recordingStartedAt: UInt64 = 0
    var sessionID = UUID()
    var timer: Timer?
    var transcribing: Task<Void, Never>?
    /// How many transcriptions are in flight. A count rather than a flag because
    /// two can overlap — see `close(utterance:)` — and the first to finish must
    /// not report the session idle while the second is still running.
    var inFlight = 0
    var observers: [NSObjectProtocol] = []

    /// **Monotonic, not the wall clock.** `expiresAt` below is a `Date` for the
    /// countdown this screen draws; the decision to end the session is taken
    /// against `CaptureClock`, for the reason that clock exists at all — a clock
    /// the user can set is a clock that can hold a microphone open past the limit
    /// they chose, or close it early. The keyboard reads the same monotonic value
    /// out of the shared page.
    var expiresAtMonotonic: UInt64 = 0

    /// Tracks the last heartbeat tick for the 1 Hz heartbeat in `poll()`.
    var lastHeartbeat: UInt64 = 0

    /// 10 Hz. The keyboard's button has to feel immediate, a page load costs
    /// nothing, and it is also how often the level the waveform draws is read off
    /// the audio thread — see `LiveRecording`.
    static let pollInterval: TimeInterval = 0.1

    static let log = Logger(subsystem: "com.nitai.aikeyboard", category: "Dictation")
}

enum DictationServiceError: Error, LocalizedError {
    case noInput
    case noConverter

    var errorDescription: String? {
        switch self {
        case .noInput: return "no audio input is available"
        case .noConverter: return "the input format cannot be converted to 16 kHz mono"
        }
    }
}
